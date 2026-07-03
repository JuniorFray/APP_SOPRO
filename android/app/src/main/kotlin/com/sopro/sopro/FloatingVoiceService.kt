package com.sopro.sopro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat

// FloatingVoiceService — exibe um botão circular flutuante sobre todos os apps.
//
// O botão permite acessar o modo de gravação de voz do Sopro sem precisar
// navegar até o app. Requer permissão SYSTEM_ALERT_WINDOW concedida pelo usuário.
//
// Comportamento do botão:
//   - Toque simples → abre o MainActivity com OPEN_VOICE=true, que dispara
//     automaticamente o FAB de gravação (via MethodChannel openVoiceFromOverlay).
//   - O Flutter recebe o evento e chama _onPressStart() no _VoiceFabState,
//     iniciando a gravação sem duplicar a lógica de áudio/Gemini.
//
// Ciclo de vida:
//   - Iniciado via MethodChannel "com.sopro.sopro/overlay" → startFloatingVoiceService()
//   - Parado via MethodChannel → stopFloatingVoiceService() ou toggle desativado
//   - Reiniciado automaticamente no próximo startup se AppInitializer detectar
//     floating_voice_enabled=true nas SharedPreferences.
class FloatingVoiceService : Service() {

    companion object {
        private const val TAG = "FloatingVoiceService"

        // Extra enviado à MainActivity ao tocar no botão flutuante
        const val EXTRA_OPEN_VOICE = "OPEN_VOICE"

        // Notificação foreground — reutiliza o canal de baixa prioridade do Dart
        private const val NOTIF_ID   = 9001
        private const val CHANNEL_ID = "sopro_background"
    }

    private var windowManager: WindowManager? = null
    private var floatingView:  View?          = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // Não inicia sem a permissão de overlay
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "SYSTEM_ALERT_WINDOW não concedido — serviço encerrado automaticamente")
            stopSelf()
            return
        }

        // Foreground obrigatório no Android 8+ para sobreviver em segundo plano
        startForeground(NOTIF_ID, buildSilentNotification())
        createOverlayButton()
        Log.d(TAG, "Botão flutuante de voz criado")
    }

    override fun onDestroy() {
        removeOverlayButton()
        Log.d(TAG, "FloatingVoiceService encerrado")
        super.onDestroy()
    }

    // ── Notificação foreground mínima ─────────────────────────────────────────

    private fun buildSilentNotification(): Notification {
        // Cria o canal caso o Dart ainda não tenha inicializado (startup muito cedo)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Sopro — Segundo plano",
                        NotificationManager.IMPORTANCE_MIN
                    ).apply { setShowBadge(false) }
                )
            }
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Sopro")
            .setContentText("Botão de voz flutuante ativo")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    // ── Janela overlay ────────────────────────────────────────────────────────

    private fun createOverlayButton() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // Botão circular com cor accent do Sopro (#E8445A)
        val btn = View(this).apply {
            setBackgroundColor(0xFFE8445A.toInt())
            // Toque simples → abre o app no modo de gravação
            setOnClickListener { openAppWithVoice() }
            // Toque longo → também abre o app (toda a lógica fica no Flutter)
            setOnLongClickListener {
                openAppWithVoice()
                true
            }
        }
        floatingView = btn

        val sizePx = dpToPx(64)

        // TYPE_APPLICATION_OVERLAY é obrigatório no Android 8+ para overlays de app
        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            sizePx, sizePx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            x = dpToPx(24)  // margem direita
            y = dpToPx(96)  // margem inferior (acima da barra de navegação)
        }

        windowManager?.addView(btn, params)
    }

    private fun removeOverlayButton() {
        floatingView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        floatingView  = null
        windowManager = null
    }

    // ── Ações do botão ────────────────────────────────────────────────────────

    // Abre o Sopro na tela principal com flag para iniciar gravação de voz.
    // FLAG_ACTIVITY_SINGLE_TOP evita criar nova instância se o app já está aberto;
    // onNewIntent() na MainActivity recebe o extra e notifica o Flutter.
    private fun openAppWithVoice() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_VOICE, true)
        }
        startActivity(intent)
        Log.d(TAG, "App aberto via botão flutuante com OPEN_VOICE=true")
    }

    // Converte dp para pixels usando a densidade real do display
    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()
}
