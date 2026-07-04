package com.sopro.sopro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

// VoiceActionReceiver — recebe comandos de voz enviados pelo FloatingVoiceService.
//
// Fluxo:
//   1. FloatingVoiceService.dispatchTriggerViaBroadcast() envia broadcast local.
//   2. Este receiver salva a ação em SharedPreferences "sopro_voice".
//   3. Inicia MainActivity com FLAG_ACTIVITY_REORDER_TO_FRONT para trazê-la ao foreground.
//   4. MainActivity.onNewIntent() lê os prefs e repassa ao Flutter via MethodChannel.
//   5. Flutter/Drift salva o trigger no banco de dados.
//
// Por que BroadcastReceiver em vez de SQLite direto?
//   O Drift mantém o DB aberto em WAL mode; escrever de outro processo (Kotlin service)
//   cria inconsistências de cache — o Drift não vê as novas linhas sem fechar/reabrir.
//   O receiver garante que o dado sempre passe pelo Drift.
class VoiceActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VoiceActionReceiver"

        // Action do broadcast — só o próprio app pode enviar (setPackage no sender)
        const val ACTION_VOICE         = "com.sopro.sopro.VOICE_ACTION"
        const val EXTRA_ACTION_JSON    = "action_json"
        const val EXTRA_PROCESS_ACTION = "PROCESS_VOICE_ACTION"

        // SharedPreferences onde a ação pendente fica até o Flutter processar
        internal const val PREFS_NAME        = "sopro_voice"
        internal const val KEY_PENDING       = "pending_action"
        internal const val KEY_PENDING_TIME  = "pending_action_time"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_VOICE) return

        val actionJson = intent.getStringExtra(EXTRA_ACTION_JSON) ?: run {
            Log.w(TAG, "Broadcast recebido sem 'action_json' — ignorado")
            return
        }
        Log.d(TAG, "VoiceAction recebida: $actionJson")

        // Persiste a ação com timestamp para que MainActivity leia em onNewIntent()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_PENDING, actionJson)
            .putLong(KEY_PENDING_TIME, System.currentTimeMillis())
            .apply()

        // Traz MainActivity ao foreground para processar a ação via Flutter/Drift.
        // FLAG_ACTIVITY_REORDER_TO_FRONT: se a activity existe na pilha, traz ao topo.
        // FLAG_ACTIVITY_SINGLE_TOP: evita recriar se já estiver no topo (→ onNewIntent).
        val startIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra(EXTRA_PROCESS_ACTION, true)
        }
        context.startActivity(startIntent)
    }
}
