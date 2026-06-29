package com.sopro.sopro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

// BroadcastReceiver ativado pelo sistema Android quando o dispositivo entra
// num geofence registrado via GeofencingClient — funciona com o app fechado/morto.
//
// O sistema entrega o Intent diretamente ao receiver (sem precisar do app em memória),
// que então dispara a notificação via NotificationManager de forma totalmente autônoma.
//
// Nota: não usa nada do Flutter Engine — é código Android puro.
class GeofenceReceiver : BroadcastReceiver() {

    companion object {
        // ID do canal de alta prioridade — mesmo ID criado pelo NotificationService Flutter
        // para que o canal já exista na maioria dos casos (app já aberto ao menos uma vez).
        private const val CHANNEL_ID   = "sopro_triggers"
        private const val CHANNEL_NAME = "Sopro — Gatilhos"

        // SharedPreferences que mapeia {environmentId → environmentName}.
        // Escrito pelo MainActivity.addNativeGeofence(); lido aqui para exibir
        // o nome do ambiente na notificação sem acesso ao banco de dados.
        const val PREFS_NAME = "geofence_names"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Lê o evento de geofence embutido no Intent pelo GeofencingClient
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return

        // Só processa ENTER — saída não precisa de notificação
        if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val nm    = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Cria o canal de alta prioridade caso o app ainda não tenha sido aberto
        // (cenário de primeiro disparo pós-instalação, antes de qualquer abertura)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply { enableVibration(true) }
            nm.createNotificationChannel(channel)
        }

        // Itera sobre cada geofence que gerou a transição de entrada
        event.triggeringGeofences?.forEach { geofence ->
            // Nome do ambiente salvo em SharedPreferences durante o addGeofence()
            val envName = prefs.getString(geofence.requestId, null) ?: return@forEach

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                // drawable monocromático — obrigatório no Android 5.0+.
                // R.mipmap.ic_launcher causaria quadrado branco na barra de status.
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle("Sopro")
                .setContentText("Você está em: $envName")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            // Usa o hash do ID do ambiente como notificationId para evitar
            // que múltiplos geofences sobrescrevam a notificação um do outro
            nm.notify(geofence.requestId.hashCode(), notification)
        }
    }
}
