package com.sopro.sopro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.SessionManager

// ReminderAlarmOverlayService — CAMINHO PRINCIPAL do alarme (alert_mode
// 'alarm'/'both'). Mostra a tela de alarme via WindowManager overlay
// (TYPE_APPLICATION_OVERLAY), o MESMO mecanismo já validado pelo
// FloatingVoiceService. Garante que o alarme apareça por cima de tudo mesmo com
// a tela DESBLOQUEADA e o usuário em OUTRO app — cenário em que o fullScreenIntent
// pode ser suprimido pelo sistema (só heads-up).
//
// Foreground service: notificação de FGS discreta e ongoing num canal próprio
// (ID != notifId do lembrete), obrigatória para o Android 8+ não matar o serviço
// enquanto o alarme toca. Iniciado por ReminderReceiver (exceção de exact-alarm
// permite iniciar FGS a partir do background).
//
// Layout + som/vibração vêm dos helpers COMPARTILHADOS AlarmScreenView +
// AlarmSoundController (mesmo visual/comportamento da ReminderAlarmActivity).
class ReminderAlarmOverlayService : Service() {

    companion object {
        // Teto de segurança: para sozinho após este tempo mesmo sem toque no Parar.
        private const val AUTO_STOP_MS = 60_000L
        // Notificação de FGS própria — ID e canal separados do lembrete.
        private const val FGS_NOTIF_ID   = 9101
        private const val FGS_CHANNEL_ID = "sopro_alarm_fgs"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var sound: AlarmSoundController? = null
    private var reminderNotifId: Int = 0
    private val autoStopHandler = Handler(Looper.getMainLooper())
    private val autoStopRunnable = Runnable { stopEverything() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        SessionManager.init(this)

        // Promove a foreground imediatamente (Android exige startForeground dentro
        // de ~5s de um startForegroundService, senão mata o processo com crash).
        if (!startAsForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Re-disparo enquanto já ativo: derruba a instância anterior antes.
        if (overlayView != null) teardownOverlay()

        val title   = intent?.getStringExtra("title") ?: "Lembrete"
        val content = intent?.getStringExtra("content") ?: ""
        reminderNotifId = intent?.getIntExtra("notif_id", 0) ?: 0

        try {
            showOverlay(title, content)
        } catch (e: Exception) {
            Logger.error("alarm_overlay_add_failed", feature = "reminders",
                action = "onStartCommand", exception = e)
            // Sem overlay não há alarme visível — encerra o serviço.
            stopEverything()
            return START_NOT_STICKY
        }

        sound = AlarmSoundController(this).also { it.start() }
        autoStopHandler.postDelayed(autoStopRunnable, AUTO_STOP_MS)
        Logger.info("alarm_overlay_shown", feature = "reminders", action = "onStartCommand",
            payload = mapOf("reminder_notif_id" to reminderNotifId.toString()))
        return START_NOT_STICKY
    }

    // Cria a janela overlay em TELA CHEIA. Mesmo padrão do FloatingVoiceService:
    // createWindowContext no Android R+ (evita BadTokenException), fallback direto
    // pré-R. Diferenças do botão de voz: SEM FLAG_NOT_FOCUSABLE (o botão Parar
    // precisa receber toque), tamanho MATCH_PARENT, e FLAG_SHOW_WHEN_LOCKED/
    // TURN_SCREEN_ON para aparecer e acender a tela mesmo bloqueada.
    private fun showOverlay(title: String, content: String) {
        windowManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val dm = getSystemService(DisplayManager::class.java)
            val display = dm.getDisplay(Display.DEFAULT_DISPLAY)!!
            createWindowContext(display, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
                .getSystemService(Context.WINDOW_SERVICE) as WindowManager
        } else {
            getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }

        val view = AlarmScreenView.build(this, title, content) { stopEverything() }
        overlayView = view

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        @Suppress("DEPRECATION")
        val windowFlags =
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutType,
            windowFlags,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START }

        windowManager?.addView(view, params)
    }

    // Notificação de FGS discreta (canal próprio IMPORTANCE_LOW). Retorna false se
    // a promoção a foreground falhar — o chamador então encerra sem crashar.
    private fun startAsForeground(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(FGS_CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(FGS_CHANNEL_ID, "Sopro — Alarme",
                        NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) }
                )
            }
        }
        val notif: Notification = NotificationCompat.Builder(this, FGS_CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Sopro")
            .setContentText("Alarme tocando")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(FGS_NOTIF_ID, notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                @Suppress("DEPRECATION")
                startForeground(FGS_NOTIF_ID, notif)
            }
            true
        } catch (e: Exception) {
            Logger.error("alarm_fgs_start_failed", feature = "reminders",
                action = "startAsForeground", exception = e)
            false
        }
    }

    private fun teardownOverlay() {
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        overlayView = null
        windowManager = null
    }

    // Para som/vibração, remove o overlay, cancela a notificação do lembrete e
    // encerra o serviço. Idempotente.
    private fun stopEverything() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        sound?.stop()
        sound = null
        teardownOverlay()
        if (reminderNotifId != 0) {
            try { NotificationManagerCompat.from(this).cancel(reminderNotifId) } catch (_: Exception) {}
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        sound?.stop()
        sound = null
        teardownOverlay()
        super.onDestroy()
    }
}
