package com.sopro.sopro

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat

// Tela cheia de ALARME de lembrete (alert_mode 'alarm' ou 'both') — CAMINHO DE
// FALLBACK, usado só quando a permissão de overlay está negada. O caminho
// principal é a ReminderAlarmOverlayService (overlay TYPE_APPLICATION_OVERLAY),
// que aparece por cima de tudo mesmo com a tela desbloqueada.
//
// Independente do Flutter Engine. Disparada via fullScreenIntent da notificação.
// Liga a tela mesmo bloqueada; som/vibração (respeitando o silencioso) e o layout
// vêm dos helpers COMPARTILHADOS AlarmSoundController + AlarmScreenView (mesma
// lógica visual/sonora do overlay). Teto de 60s como rede de segurança.
class ReminderAlarmActivity : Activity() {

    companion object {
        // Teto de segurança: para sozinho após este tempo mesmo sem toque no Parar.
        private const val AUTO_STOP_MS = 60_000L
    }

    private var sound: AlarmSoundController? = null
    private var notifId: Int = 0
    private val autoStopHandler = Handler(Looper.getMainLooper())
    private val autoStopRunnable = Runnable { stopAndFinish() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Mostrar sobre a tela de bloqueio e ligar a tela.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { // API 27+
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val title   = intent.getStringExtra("title") ?: "Lembrete"
        val content = intent.getStringExtra("content") ?: ""
        notifId     = intent.getIntExtra("notif_id", 0)

        // Layout + som/vibração vêm dos helpers compartilhados com o overlay.
        setContentView(AlarmScreenView.build(this, title, content) { stopAndFinish() })
        sound = AlarmSoundController(this).also { it.start() }

        // Rede de segurança: encerra sozinho depois do teto.
        autoStopHandler.postDelayed(autoStopRunnable, AUTO_STOP_MS)
    }

    // Ação do botão Parar (e do teto de tempo): silencia, remove a notificação e
    // fecha a Activity.
    private fun stopAndFinish() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        sound?.stop()
        sound = null
        if (notifId != 0) {
            try { NotificationManagerCompat.from(this).cancel(notifId) } catch (_: Exception) {}
        }
        finish()
    }

    // Garante que nada fica tocando se a Activity for destruída por outro caminho
    // (usuário aperta home, sistema mata, etc.).
    override fun onDestroy() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        sound?.stop()
        sound = null
        super.onDestroy()
    }
}
