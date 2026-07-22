package com.sopro.sopro

import android.app.Activity
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationManagerCompat

// Tela cheia de ALARME de lembrete (alert_mode 'alarm' ou 'both').
//
// Independente do Flutter Engine — mesma filosofia do ReminderReceiver/
// GeofenceReceiver. Disparada via fullScreenIntent da notificação. Liga a tela
// mesmo bloqueada, toca som/vibra em loop RESPEITANDO o modo silencioso do
// aparelho (só botão Parar, sem soneca) e tem um teto de 60s como rede de
// segurança para nunca ficar tocando pra sempre.
class ReminderAlarmActivity : Activity() {

    companion object {
        // Teto de segurança: para sozinho após este tempo mesmo sem toque no Parar.
        private const val AUTO_STOP_MS = 60_000L
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
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

        setContentView(buildLayout(title, content))
        startAlerting()

        // Rede de segurança: encerra sozinho depois do teto.
        autoStopHandler.postDelayed(autoStopRunnable, AUTO_STOP_MS)
    }

    // Layout 100% programático (sem XML): fundo escuro, título, conteúdo e botão
    // grande "Parar".
    private fun buildLayout(title: String, content: String): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0E0F13"))
            setPadding(48, 48, 48, 48)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val titleView = TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 30f
            gravity = Gravity.CENTER
        }
        root.addView(titleView)

        if (content.isNotEmpty()) {
            val contentView = TextView(this).apply {
                text = content
                setTextColor(Color.parseColor("#B9BCC6"))
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 0)
            }
            root.addView(contentView)
        }

        val stopButton = Button(this).apply {
            text = "Parar"
            textSize = 20f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#FF6B5B")) // accent coral
            setPadding(0, 32, 0, 32)
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 64 }
            layoutParams = lp
            setOnClickListener { stopAndFinish() }
        }
        root.addView(stopButton)

        return root
    }

    // Toca/vibra conforme o modo do toque do aparelho — respeita o silencioso.
    private fun startAlerting() {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        when (audio.ringerMode) {
            AudioManager.RINGER_MODE_NORMAL  -> startSound()
            AudioManager.RINGER_MODE_VIBRATE -> startVibration()
            AudioManager.RINGER_MODE_SILENT  -> { /* silencioso: só a tela */ }
        }
    }

    // Som de alarme em loop (default do sistema). Fallback para notificação/toque.
    private fun startSound() {
        val uri: Uri =
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                ?: return
        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(this@ReminderAlarmActivity, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Falha ao tocar não pode travar a tela — segue só visual.
            mediaPlayer = null
        }
    }

    // Vibração em loop (para o modo vibrar).
    private fun startVibration() {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        vibrator = v
        // Padrão: 500ms vibra, 500ms pausa, repetindo do índice 0.
        val pattern = longArrayOf(0, 500, 500)
        v.vibrate(VibrationEffect.createWaveform(pattern, 0))
    }

    // Para som + vibração. Idempotente.
    private fun stopAlerting() {
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
    }

    // Ação do botão Parar (e do teto de tempo): silencia, remove a notificação e
    // fecha a Activity.
    private fun stopAndFinish() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        stopAlerting()
        if (notifId != 0) {
            try { NotificationManagerCompat.from(this).cancel(notifId) } catch (_: Exception) {}
        }
        finish()
    }

    // Garante que nada fica tocando se a Activity for destruída por outro caminho
    // (usuário aperta home, sistema mata, etc.).
    override fun onDestroy() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        stopAlerting()
        super.onDestroy()
    }
}
