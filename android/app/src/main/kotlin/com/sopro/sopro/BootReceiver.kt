package com.sopro.sopro

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.LoggerConfiguration
import com.sopro.sopro.logging.SessionManager
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

// Re-registra todos os geofences do banco após reinicialização do dispositivo.
//
// O Android destrói todos os geofences registrados pelo GeofencingClient quando
// o dispositivo é desligado ou reiniciado. Sem este receiver o usuário não recebe
// notificações de localização até reabrir o app manualmente.
//
// Fluxo ao receber BOOT_COMPLETED:
//   1. Abre sopro.db via SQLite nativo (sem Flutter Engine)
//   2. Lê todos os ambientes (id, name, lat, lng, radius)
//   3. Re-registra no GeofencingClient com FLAG_MUTABLE + NEVER_EXPIRE
//   4. Atualiza SharedPreferences {envId → envName} usadas pelo GeofenceReceiver
//   5. Loga "geofence_boot_reregistered" no Supabase para confirmar funcionamento
//
// Declarado no AndroidManifest com RECEIVE_BOOT_COMPLETED e exported="true".
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"

        // Mesmo endpoint e chave do AppLogger.dart — INSERT-only por RLS no Supabase
        private const val SUPABASE_URL =
            "https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs"
        private const val SUPABASE_KEY =
            "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"
    }

    override fun onReceive(context: Context, intent: Intent) {
        SessionManager.init(context)
        val receiverStart = System.currentTimeMillis()
        val corrId = CorrelationManager.beginOperation("boot_receiver")

        val action = intent.action
        Logger.debug("broadcast_received", feature = "boot", action = action ?: "null_action",
            correlationId = corrId,
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("action" to (action ?: "null")) else null)

        // Reconhece as actions possíveis para logar antes de filtrar.
        // Só processa BOOT_COMPLETED — demais são ignoradas.
        if (action != Intent.ACTION_BOOT_COMPLETED) {
            val actionLabel = when (action) {
                "android.intent.action.LOCKED_BOOT_COMPLETED" -> "LOCKED_BOOT_COMPLETED"
                Intent.ACTION_MY_PACKAGE_REPLACED              -> "MY_PACKAGE_REPLACED"
                Intent.ACTION_PACKAGE_REPLACED                 -> "PACKAGE_REPLACED"
                "android.intent.action.QUICKBOOT_POWERON"      -> "QUICKBOOT_POWERON"
                else                                            -> action ?: "null"
            }
            Logger.debug("action_ignored", feature = "boot",
                correlationId = corrId,
                payload = mapOf("action" to actionLabel),
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("boot_receiver")
            return
        }

        Logger.info("boot_completed_received", feature = "boot", action = "onReceive",
            correlationId = corrId)

        // goAsync() permite tarefas longas dentro do BroadcastReceiver.
        // Sem ele o sistema pode matar o processo antes do trabalho terminar (~10s limit).
        val pendingResult = goAsync()

        // Thread dedicada para operações de I/O (banco + rede) fora do main thread
        Executors.newSingleThreadExecutor().execute {
            try {
                val environments = readEnvironmentsFromDb(context, corrId)
                if (environments.isNotEmpty()) {
                    registerGeofences(context, environments, corrId)
                    Logger.info("geofence_boot_reregistered", feature = "boot",
                        action = "onReceive", correlationId = corrId,
                        payload = mapOf("count" to environments.size.toString()))
                    logToSupabase(context, environments.size)
                } else {
                    Logger.debug("no_environments_to_register", feature = "boot",
                        action = "onReceive", correlationId = corrId)
                }

                // Reagenda lembretes ativos — o Android descarta alarmes exatos no
                // reboot, igual aos geofences. Sem isso, lembretes pendentes nunca
                // disparam até o app ser reaberto.
                val reminders = readActiveRemindersFromDb(context, corrId)
                reminders.forEach { r ->
                    ReminderScheduler.scheduleExact(context, r.id, r.triggerAt)
                }
                if (reminders.isNotEmpty()) {
                    Logger.info("reminders_boot_rescheduled", feature = "boot",
                        action = "onReceive", correlationId = corrId,
                        payload = mapOf("count" to reminders.size.toString()))
                }

                // Reagenda a notificação diária de clima se estava ativa — o
                // Android descarta alarmes exatos no reboot, igual aos lembretes.
                val fprefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (fprefs.getBoolean("flutter.weather_notification_enabled", false)) {
                    val hour = fprefs.getLong("flutter.weather_notification_hour", 8L).toInt()
                    val minute = fprefs.getLong("flutter.weather_notification_minute", 0L).toInt()
                    WeatherNotificationScheduler.schedule(context, hour, minute)
                    Logger.info("weather_notification_boot_rescheduled", feature = "boot",
                        action = "onReceive", correlationId = corrId,
                        payload = mapOf("hour" to hour.toString(), "minute" to minute.toString()))
                }

                Logger.info("receiver_finished", feature = "boot", action = "onReceive",
                    correlationId = corrId,
                    durationMs = System.currentTimeMillis() - receiverStart,
                    payload = mapOf("environments_count" to environments.size.toString()))
            } catch (e: Exception) {
                Logger.error("boot_reregister_failed", feature = "boot", action = "onReceive",
                    correlationId = corrId, exception = e,
                    durationMs = System.currentTimeMillis() - receiverStart)
            } finally {
                // Sempre finaliza a operação, independente de sucesso ou falha.
                // pendingResult.finish() libera o BroadcastReceiver após o I/O.
                CorrelationManager.endOperation("boot_receiver")
                pendingResult.finish()
            }
        }
    }

    // Abre o banco SQLite do Sopro e lê todos os ambientes cadastrados.
    // Drift (drift_flutter) armazena o banco em getApplicationDocumentsDirectory(),
    // que no Android mapeia para filesDir.parent/app_flutter/sopro.db.
    // Tenta múltiplos caminhos para cobrir variações entre versões do package.
    private fun readEnvironmentsFromDb(context: Context, corrId: String): List<EnvironmentRow> {
        val dbStart = System.currentTimeMillis()
        val candidates = listOf(
            File(context.filesDir.parentFile, "app_flutter/sopro.db"),
            File(context.filesDir, "sopro.db"),
            context.getDatabasePath("sopro.db"),
        )

        val dbFile = candidates.firstOrNull { it.exists() } ?: run {
            Logger.warn("sqlite_db_not_found", feature = "boot",
                action = "readEnvironmentsFromDb", correlationId = corrId,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("paths_tried" to candidates.map { it.absolutePath }.toString())
                else mapOf("paths_count" to candidates.size.toString()))
            return emptyList()
        }

        Logger.debug("sqlite_db_found", feature = "boot", action = "readEnvironmentsFromDb",
            correlationId = corrId,
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("path" to dbFile.absolutePath) else null)

        val rows = mutableListOf<EnvironmentRow>()
        try {
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY
            ).use { db ->
                Logger.debug("sqlite_opened", feature = "boot",
                    action = "readEnvironmentsFromDb", correlationId = corrId)
                db.rawQuery(
                    "SELECT id, name, latitude, longitude, radius_meters FROM environments",
                    null
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        rows.add(
                            EnvironmentRow(
                                id     = cursor.getString(0),
                                name   = cursor.getString(1),
                                lat    = cursor.getDouble(2),
                                lng    = cursor.getDouble(3),
                                radius = cursor.getDouble(4).toFloat(),
                            )
                        )
                    }
                }
            }
            Logger.debug("sqlite_environments_loaded", feature = "boot",
                action = "readEnvironmentsFromDb", correlationId = corrId,
                durationMs = System.currentTimeMillis() - dbStart,
                payload = mapOf("count" to rows.size.toString()))
        } catch (e: Exception) {
            Logger.error("sqlite_read_environments_failed", feature = "boot",
                action = "readEnvironmentsFromDb", correlationId = corrId, exception = e,
                durationMs = System.currentTimeMillis() - dbStart)
        }
        return rows
    }

    // Lê os lembretes ATIVOS do banco (id + scheduled_at) para reagendar após
    // reboot. Mesmo padrão de readEnvironmentsFromDb (READONLY + finally close).
    private fun readActiveRemindersFromDb(context: Context, corrId: String): List<ReminderRow> {
        val candidates = listOf(
            File(context.filesDir.parentFile, "app_flutter/sopro.db"),
            File(context.filesDir, "sopro.db"),
            context.getDatabasePath("sopro.db"),
        )
        val dbFile = candidates.firstOrNull { it.exists() } ?: return emptyList()

        val rows = mutableListOf<ReminderRow>()
        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
            db.rawQuery(
                "SELECT id, scheduled_at FROM scheduled_reminders WHERE is_active = 1",
                null
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    // Drift grava scheduled_at em SEGUNDOS; scheduleExact espera MILLIS.
                    rows.add(ReminderRow(
                        id = cursor.getString(0),
                        triggerAt = cursor.getLong(1) * 1000L))
                }
            }
        } catch (e: Exception) {
            Logger.warn("sqlite_read_reminders_failed", feature = "boot",
                action = "readActiveRemindersFromDb", correlationId = corrId, exception = e)
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
        return rows
    }

    // Registra todos os ambientes como geofences circulares permanentes.
    // Idêntico ao fluxo de addNativeGeofence() na MainActivity, mas sem
    // retorno de MethodChannel — opera completamente sem o Flutter Engine.
    @SuppressLint("MissingPermission")
    private fun registerGeofences(
        context: Context,
        environments: List<EnvironmentRow>,
        corrId: String,
    ) {
        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Logger.warn("geofence_permission_denied", feature = "boot",
                action = "registerGeofences", correlationId = corrId,
                payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
            return
        }

        val geofenceStart = System.currentTimeMillis()

        val geofences = environments.map { env ->
            Geofence.Builder()
                .setRequestId(env.id)
                .setCircularRegion(env.lat, env.lng, env.radius)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0) // não dispara imediatamente ao registrar
            .addGeofences(geofences)
            .build()

        // FLAG_MUTABLE obrigatório no Android 12+ para o GeofencingClient injetar
        // dados da transição no Intent antes de entregá-lo ao GeofenceReceiver.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, GeofenceReceiver::class.java),
            flags
        )

        // Atualiza SharedPreferences com nomes dos ambientes para uso offline
        // pelo GeofenceReceiver (exibe nome no push sem acessar o banco)
        val editor = context
            .getSharedPreferences(GeofenceReceiver.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
        environments.forEach { env -> editor.putString(env.id, env.name) }
        editor.apply()

        Logger.debug("geofence_register_start", feature = "boot",
            action = "registerGeofences", correlationId = corrId,
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("count" to environments.size.toString(),
                    "env_ids" to environments.map { it.id }.toString())
            else mapOf("count" to environments.size.toString()))

        LocationServices.getGeofencingClient(context)
            .addGeofences(request, pendingIntent)
            .addOnSuccessListener {
                Logger.info("geofences_registered", feature = "boot",
                    action = "registerGeofences", correlationId = corrId,
                    durationMs = System.currentTimeMillis() - geofenceStart,
                    payload = mapOf("count" to environments.size.toString()))
            }
            .addOnFailureListener { e ->
                Logger.error("geofences_register_failed", feature = "boot",
                    action = "registerGeofences", correlationId = corrId, exception = e,
                    durationMs = System.currentTimeMillis() - geofenceStart,
                    payload = mapOf("count" to environments.size.toString()))
            }
    }

    // Loga no Supabase que o boot receiver funcionou — fire-and-forget, falhas silenciosas.
    // Lê o device_id das SharedPreferences do Flutter (prefixo "flutter.").
    // Mantido como transporte legado até o Logger Kotlin receber sink Supabase.
    private fun logToSupabase(context: Context, count: Int) {
        try {
            val prefs    = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val deviceId = prefs.getString("flutter.logger_device_id", null) ?: return

            val body = JSONObject().apply {
                put("device_id",  deviceId)
                put("event_type", "geofence_boot_reregistered")
                put("payload",    JSONObject().put("count", count))
            }.toString()

            val conn = (URL(SUPABASE_URL).openConnection() as HttpURLConnection).apply {
                requestMethod  = "POST"
                connectTimeout = 5_000
                readTimeout    = 5_000
                doOutput       = true
                setRequestProperty("apikey",        SUPABASE_KEY)
                setRequestProperty("Authorization", "Bearer $SUPABASE_KEY")
                // HOTFIX 2 — charset explícito evita mojibake nos acentos (UTF-8 lido como Latin-1)
                setRequestProperty("Content-Type",  "application/json; charset=utf-8")
                setRequestProperty("Prefer",        "return=minimal")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }
            conn.inputStream.use { it.readBytes() } // consome a resposta para liberar conexão
            conn.disconnect()
            Logger.trace("supabase_sent", feature = "boot", action = "logToSupabase",
                payload = mapOf("event_type" to "geofence_boot_reregistered"))
        } catch (e: Exception) {
            // Logging nunca pode bloquear o re-registro de geofences
            Logger.trace("supabase_send_failed", feature = "boot", action = "logToSupabase",
                exception = e)
        }
    }

    // Dados mínimos de um ambiente para registro de geofence
    data class EnvironmentRow(
        val id:     String,
        val name:   String,
        val lat:    Double,
        val lng:    Double,
        val radius: Float,
    )

    // Dados mínimos de um lembrete para reagendar o alarme após reboot
    data class ReminderRow(
        val id:        String,
        val triggerAt: Long,
    )
}
