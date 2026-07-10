package com.sopro.sopro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.LoggerConfiguration
import com.sopro.sopro.logging.SessionManager
import java.io.File

// BroadcastReceiver ativado pelo sistema Android quando o dispositivo entra
// num geofence registrado via GeofencingClient — funciona com o app fechado/morto.
//
// Fluxo dentro de onReceive():
//   1. Valida o evento (null / error / tipo de transição)
//   2. Checa permissão POST_NOTIFICATIONS (Android 13+) via areNotificationsEnabled()
//   3. CRIA O CANAL antes de qualquer notify() — obrigatório no Android 8+.
//      Usa getNotificationChannel() para só criar se ainda não existir.
//   4. Para cada geofence trigado, lê o nome das SharedPreferences e dispara notify().
//
// Nota: não usa nada do Flutter Engine — é código Android puro.
class GeofenceReceiver : BroadcastReceiver() {

    companion object {
        // CHANNEL_ID DEVE ser idêntico ao definido em NotificationService.dart:
        //   _triggerChannelId = 'sopro_triggers'
        // Qualquer divergência faz o notify() ser descartado silenciosamente pelo Android.
        private const val CHANNEL_ID   = "sopro_triggers" // ← mesmo valor do Dart
        private const val CHANNEL_NAME = "Sopro — Gatilhos"

        private const val TAG = "GeofenceReceiver"

        // SharedPreferences que mapeia {environmentId → environmentName}.
        // Escrito pelo MainActivity.addNativeGeofence() quando o Dart registra o geofence.
        // Lido aqui para exibir o nome do ambiente sem acesso ao banco de dados Flutter.
        const val PREFS_NAME = "geofence_names"
    }

    override fun onReceive(context: Context, intent: Intent) {
        SessionManager.init(context)
        val receiverStart = System.currentTimeMillis()
        val corrId = CorrelationManager.beginOperation("geofence_event")

        Logger.debug("broadcast_received", feature = "geofence", action = "onReceive",
            correlationId = corrId)

        // ── 1. Valida o evento ──────────────────────────────────────────────────
        val event = GeofencingEvent.fromIntent(intent)
        if (event == null) {
            Logger.warn("geofencing_event_null", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("geofence_event")
            return
        }

        if (event.hasError()) {
            Logger.error("geofencing_event_error", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                payload = mapOf("error_code" to event.errorCode.toString()),
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("geofence_event")
            return
        }

        Logger.debug("geofencing_event_created", feature = "geofence", action = "onReceive",
            correlationId = corrId)

        // Só processa ENTER — saída não gera notificação
        val transition = event.geofenceTransition
        if (transition != Geofence.GEOFENCE_TRANSITION_ENTER) {
            val transitionName = when (transition) {
                Geofence.GEOFENCE_TRANSITION_EXIT  -> "EXIT"
                Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
                else -> "UNKNOWN($transition)"
            }
            Logger.debug("geofence_transition_skipped", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                payload = mapOf("transition" to transitionName),
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("geofence_event")
            return
        }

        val geofences = event.triggeringGeofences
        val geofenceCount = geofences?.size ?: 0
        Logger.info("geofence_transition_enter", feature = "geofence", action = "onReceive",
            correlationId = corrId,
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("geofence_count" to geofenceCount.toString(),
                    "request_ids" to (geofences?.map { it.requestId }?.toString() ?: "[]"))
            else mapOf("geofence_count" to geofenceCount.toString()))

        if (geofences.isNullOrEmpty()) {
            Logger.warn("geofencing_no_triggers", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("geofence_event")
            return
        }

        // ── 2. Verifica permissão de notificação ────────────────────────────────
        // NotificationManagerCompat.areNotificationsEnabled() cobre:
        //   • Android 13+ (API 33): POST_NOTIFICATIONS concedida pelo usuário
        //   • Android < 13: verifica se o app não foi silenciado nas configurações
        // Se retornar false, notify() seria descartado silenciosamente — melhor sair.
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            Logger.warn("notification_permission_denied", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                durationMs = System.currentTimeMillis() - receiverStart)
            CorrelationManager.endOperation("geofence_event")
            return
        }

        // ── 3. Garante que o canal existe ANTES do primeiro notify() ────────────
        // No Android 8+ (API 26+) notificações enviadas para um canal inexistente
        // são descartadas silenciosamente — sem exception, sem logcat.
        //
        // Situação: app nunca foi aberto → NotificationService.initialize() nunca rodou
        //           → canal 'sopro_triggers' não existe → notify() silenciosamente ignorado.
        //
        // IMPORTANTE: usar IMPORTANCE_MAX (não HIGH). OEMs restritivos como Motorola My UX
        // ignoram notificações IMPORTANCE_HIGH de apps em background — exigem MAX para
        // garantir heads-up. Mesmo canal e mesma importância usados pelo Dart (Sprint 13).
        // createNotificationChannel() é idempotente: se o canal já existe com MAX (criado
        // pelo NotificationService.initialize()), o Android mantém as configurações do
        // usuário e ignora esta chamada.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_MAX  // deve ser MAX, não HIGH
                ).apply {
                    enableVibration(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(channel)
                Logger.debug("notification_channel_created", feature = "geofence",
                    action = "onReceive", correlationId = corrId,
                    payload = mapOf("channel_id" to CHANNEL_ID, "importance" to "MAX"))
            }
        }

        // ── 4. Dispara notificação para cada geofence trigado ───────────────────
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        geofences.forEach { geofence ->
            // Nome salvo pelo MainActivity.addNativeGeofence() — fallback se ausente.
            val envName = prefs.getString(geofence.requestId, null)
            if (envName == null) {
                Logger.warn("environment_not_found", feature = "geofence", action = "onReceive",
                    correlationId = corrId,
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("request_id" to geofence.requestId) else null)
            } else {
                Logger.debug("environment_found", feature = "geofence", action = "onReceive",
                    correlationId = corrId,
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("environment_name" to envName,
                            "request_id" to geofence.requestId)
                    else null)
            }
            val resolvedEnvName = envName ?: "um local Sopro"

            // Lê o primeiro gatilho ativo do ambiente diretamente do SQLite
            // (sem Flutter Engine) para construir a mensagem contextual.
            val triggerTitle = readFirstTriggerTitle(context, geofence.requestId, corrId)
            val notifBody    = buildNotificationBody(triggerTitle, resolvedEnvName)

            // Título: título do gatilho (se encontrado) ou "Sopro — envName"
            val notifTitle = if (!triggerTitle.isNullOrEmpty()) triggerTitle
                             else "Sopro — $resolvedEnvName"

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle(notifTitle)
                .setContentText(notifBody)
                // ticker força heads-up em OEMs restritivos (Motorola My UX, etc.)
                .setTicker("Sopro — $resolvedEnvName")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .build()

            Logger.debug("notification_sending", feature = "geofence", action = "onReceive",
                correlationId = corrId,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to resolvedEnvName,
                        "trigger_name" to (triggerTitle ?: ""),
                        "notification_id" to geofence.requestId.hashCode().toString())
                else null)

            val notifStart = System.currentTimeMillis()
            try {
                nmCompat.notify(geofence.requestId.hashCode(), notification)
                Logger.info("notification_sent", feature = "geofence", action = "onReceive",
                    correlationId = corrId,
                    durationMs = System.currentTimeMillis() - notifStart,
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("environment_name" to resolvedEnvName,
                            "trigger_name" to (triggerTitle ?: ""),
                            "notification_id" to geofence.requestId.hashCode().toString())
                    else mapOf("notification_id" to geofence.requestId.hashCode().toString()))
            } catch (e: SecurityException) {
                Logger.error("notification_send_failed", feature = "geofence",
                    action = "onReceive", correlationId = corrId, exception = e,
                    durationMs = System.currentTimeMillis() - notifStart,
                    payload = mapOf("notification_id" to geofence.requestId.hashCode().toString()))
            }
        }

        Logger.info("receiver_finished", feature = "geofence", action = "onReceive",
            correlationId = corrId,
            durationMs = System.currentTimeMillis() - receiverStart,
            payload = mapOf("geofence_count" to geofenceCount.toString()))
        CorrelationManager.endOperation("geofence_event")
    }

    // ── Helpers privados ───────────────────────────────────────────────────────

    // Lê o título do primeiro gatilho ativo do ambiente a partir do SQLite.
    // Tenta os mesmos caminhos que o BootReceiver — sem Flutter Engine.
    // Retorna null se o banco não for encontrado ou não houver gatilhos.
    //
    // Segue o padrão obrigatório do projeto: var db fora do try + finally db?.close().
    private fun readFirstTriggerTitle(
        context: Context,
        environmentId: String,
        corrId: String,
    ): String? {
        val dbPaths = listOf(
            File(context.filesDir.parentFile, "app_flutter/sopro.db"),
            context.getDatabasePath("sopro.db"),
        )
        for (dbFile in dbPaths) {
            if (!dbFile.exists()) continue
            val queryStart = System.currentTimeMillis()
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY
                )
                Logger.debug("sqlite_opened", feature = "geofence",
                    action = "readFirstTriggerTitle", correlationId = corrId,
                    payload = mapOf("path" to dbFile.name))

                val cursor = db.rawQuery(
                    "SELECT title FROM triggers WHERE environment_id = ? " +
                    "AND is_active = 1 ORDER BY created_at ASC LIMIT 1",
                    arrayOf(environmentId)
                )
                val title = if (cursor.moveToFirst()) cursor.getString(0) else null
                cursor.close()

                val duration = System.currentTimeMillis() - queryStart
                if (!title.isNullOrEmpty()) {
                    Logger.debug("sqlite_trigger_found", feature = "geofence",
                        action = "readFirstTriggerTitle", correlationId = corrId,
                        durationMs = duration,
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("trigger_name" to title) else null)
                } else {
                    Logger.debug("sqlite_trigger_not_found", feature = "geofence",
                        action = "readFirstTriggerTitle", correlationId = corrId,
                        durationMs = duration,
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("environment_id" to environmentId) else null)
                }
                return title?.takeIf { it.isNotEmpty() }
            } catch (e: Exception) {
                Logger.warn("sqlite_read_trigger_failed", feature = "geofence",
                    action = "readFirstTriggerTitle", correlationId = corrId, exception = e,
                    durationMs = System.currentTimeMillis() - queryStart,
                    payload = mapOf("path" to dbFile.name))
            } finally {
                try { db?.close() } catch (e: Exception) {
                    Logger.warn("sqlite_close_failed", feature = "geofence",
                        action = "readFirstTriggerTitle", correlationId = corrId, exception = e)
                }
            }
        }
        return null
    }

    // Constrói a mensagem do corpo da notificação com base nas palavras-chave
    // do título do gatilho — mesma lógica do FireTriggersUseCase no Dart.
    private fun buildNotificationBody(triggerTitle: String?, envName: String): String {
        if (triggerTitle.isNullOrEmpty()) {
            return "Você chegou em $envName. Hora dos seus lembretes!"
        }
        val lower = triggerTitle.lowercase()
        return when {
            listOf("comprar", "buscar", "pegar", "trazer").any { lower.contains(it) } ->
                "Você está em $envName. Lembrou de $triggerTitle?"
            listOf("falar", "ligar", "contatar", "avisar", "perguntar").any { lower.contains(it) } ->
                "Você chegou em $envName. Não esqueça de $triggerTitle."
            listOf("verificar", "checar", "conferir", "inspecionar").any { lower.contains(it) } ->
                "Você está em $envName. $triggerTitle."
            listOf("pagar", "renovar", "assinar", "entregar").any { lower.contains(it) } ->
                "Você chegou em $envName. Atenção: $triggerTitle."
            else ->
                "Você chegou em $envName. Hora de ${triggerTitle.lowercase()}!"
        }
    }
}
