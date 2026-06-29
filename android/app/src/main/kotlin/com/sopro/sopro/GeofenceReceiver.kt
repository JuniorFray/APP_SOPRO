package com.sopro.sopro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

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
        // ── 1. Valida o evento ──────────────────────────────────────────────────
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            Log.e(TAG, "GeofencingEvent com erro: ${event.errorCode}")
            return
        }
        // Só processa ENTER — saída não gera notificação
        if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return

        // ── 2. Verifica permissão de notificação ────────────────────────────────
        // NotificationManagerCompat.areNotificationsEnabled() cobre:
        //   • Android 13+ (API 33): POST_NOTIFICATIONS concedida pelo usuário
        //   • Android < 13: verifica se o app não foi silenciado nas configurações
        // Se retornar false, notify() seria descartado silenciosamente — melhor sair.
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            Log.w(TAG, "Notificações desabilitadas para o app — geofence enter ignorado")
            return
        }

        // ── 3. Garante que o canal existe ANTES do primeiro notify() ────────────
        // No Android 8+ (API 26+) notificações enviadas para um canal inexistente
        // são descartadas silenciosamente — sem exception, sem logcat.
        //
        // Situação: app nunca foi aberto → NotificationService.initialize() nunca rodou
        //           → canal 'sopro_triggers' não existe → notify() silenciosamente ignorado.
        //
        // getNotificationChannel() retorna null se o canal ainda não foi criado.
        // createNotificationChannel() é idempotente: se o canal já existe,
        // o Android mantém as configurações do usuário e ignora a chamada.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { enableVibration(true) }
                nm.createNotificationChannel(channel)
                Log.d(TAG, "Canal '$CHANNEL_ID' criado pelo GeofenceReceiver (app nunca aberto)")
            }
        }

        // ── 4. Dispara notificação para cada geofence trigado ───────────────────
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        event.triggeringGeofences?.forEach { geofence ->
            // Nome salvo pelo MainActivity.addNativeGeofence() — fallback se ausente.
            // Antes usávamos return@forEach (notification silenciada), agora exibe
            // mesmo sem nome: evita sumir a notificação por prefs vazia/desatualizada.
            val envName = prefs.getString(geofence.requestId, null) ?: "um local Sopro"

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                // drawable monocromático (res/drawable/notification_icon.xml) —
                // obrigatório desde Android 5.0. @mipmap/ic_launcher → quadrado branco.
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle("Sopro")
                .setContentText("Você está em: $envName")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            try {
                // nmCompat.notify() lida com SecurityException internamente no Android 13+
                // quando POST_NOTIFICATIONS não está concedida (embora já checamos acima).
                nmCompat.notify(geofence.requestId.hashCode(), notification)
                Log.d(TAG, "Notificação disparada: '$envName' (id=${geofence.requestId.hashCode()})")
            } catch (e: SecurityException) {
                // Segurança extra: caso POST_NOTIFICATIONS seja revogada entre o check e o notify
                Log.e(TAG, "SecurityException ao disparar notificação: ${e.message}")
            }
        }
    }
}
