package com.sopro.sopro

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

// AlarmSoundController — som + vibração de alarme, respeitando o ringerMode do
// aparelho (NORMAL toca, VIBRATE vibra, SILENT fica mudo). Extraído da antiga
// ReminderAlarmActivity para ser COMPARTILHADO entre ela (fullScreenIntent) e a
// ReminderAlarmOverlayService (overlay TYPE_APPLICATION_OVERLAY) — mesma lógica,
// sem duplicar. Cuida só de tocar/parar; o ciclo de vida (teto de 60s, remover
// view, cancelar notificação) fica com quem usa.
class AlarmSoundController(private val context: Context) {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    // Toca/vibra conforme o modo do toque do aparelho — respeita o silencioso.
    fun start() {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (audio.ringerMode) {
            AudioManager.RINGER_MODE_NORMAL  -> startSound()
            AudioManager.RINGER_MODE_VIBRATE -> startVibration()
            AudioManager.RINGER_MODE_SILENT  -> { /* silencioso: só a tela */ }
        }
    }

    // Som de alarme em loop (default do sistema). Fallback para notificação/toque.
    private fun startSound() {
        val uri: Uri =
            RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                ?: return
        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(context, uri)
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
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator = v
        // Padrão: 500ms vibra, 500ms pausa, repetindo do índice 0.
        val pattern = longArrayOf(0, 500, 500)
        v.vibrate(VibrationEffect.createWaveform(pattern, 0))
    }

    // Para som + vibração. Idempotente.
    fun stop() {
        try { mediaPlayer?.stop(); mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
    }
}
