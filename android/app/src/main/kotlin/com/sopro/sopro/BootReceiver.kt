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
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
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
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.d(TAG, "BOOT_COMPLETED recebido — re-registrando geofences")

        // goAsync() permite tarefas longas dentro do BroadcastReceiver.
        // Sem ele o sistema pode matar o processo antes do trabalho terminar (~10s limit).
        val pendingResult = goAsync()

        // Thread dedicada para operações de I/O (banco + rede) fora do main thread
        Executors.newSingleThreadExecutor().execute {
            try {
                val environments = readEnvironmentsFromDb(context)
                Log.d(TAG, "${environments.size} ambiente(s) encontrado(s) no banco")
                if (environments.isNotEmpty()) {
                    registerGeofences(context, environments)
                    logToSupabase(context, environments.size)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Erro ao re-registrar geofences pós-boot: ${e.message}", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    // Abre o banco SQLite do Sopro e lê todos os ambientes cadastrados.
    // Drift (drift_flutter) armazena o banco em getApplicationDocumentsDirectory(),
    // que no Android mapeia para filesDir.parent/app_flutter/sopro.db.
    // Tenta múltiplos caminhos para cobrir variações entre versões do package.
    private fun readEnvironmentsFromDb(context: Context): List<EnvironmentRow> {
        val candidates = listOf(
            File(context.filesDir.parentFile, "app_flutter/sopro.db"),
            File(context.filesDir, "sopro.db"),
            context.getDatabasePath("sopro.db"),
        )

        val dbFile = candidates.firstOrNull { it.exists() } ?: run {
            Log.w(TAG, "sopro.db não encontrado. Caminhos tentados:")
            candidates.forEach { Log.w(TAG, "  → ${it.absolutePath}") }
            return emptyList()
        }
        Log.d(TAG, "Banco encontrado: ${dbFile.absolutePath}")

        val rows = mutableListOf<EnvironmentRow>()
        try {
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY
            ).use { db ->
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
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao ler environments: ${e.message}", e)
        }
        return rows
    }

    // Registra todos os ambientes como geofences circulares permanentes.
    // Idêntico ao fluxo de addNativeGeofence() na MainActivity, mas sem
    // retorno de MethodChannel — opera completamente sem o Flutter Engine.
    @SuppressLint("MissingPermission")
    private fun registerGeofences(context: Context, environments: List<EnvironmentRow>) {
        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "ACCESS_FINE_LOCATION não concedido — abortando re-registro")
            return
        }

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

        LocationServices.getGeofencingClient(context)
            .addGeofences(request, pendingIntent)
            .addOnSuccessListener {
                Log.d(TAG, "${environments.size} geofence(s) re-registrado(s) com sucesso")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Falha ao re-registrar geofences: ${e.message}", e)
            }
    }

    // Loga no Supabase que o boot receiver funcionou — fire-and-forget, falhas silenciosas.
    // Lê o device_id das SharedPreferences do Flutter (prefixo "flutter.").
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
                setRequestProperty("Content-Type",  "application/json")
                setRequestProperty("Prefer",        "return=minimal")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }
            conn.inputStream.use { it.readBytes() } // consome a resposta para liberar conexão
            conn.disconnect()
            Log.d(TAG, "geofence_boot_reregistered logado no Supabase (count=$count)")
        } catch (e: Exception) {
            // Logging nunca pode bloquear o re-registro de geofences
            Log.w(TAG, "Falha ao logar no Supabase: ${e.message}")
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
}
