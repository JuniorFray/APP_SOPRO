package com.sopro.sopro

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView

// Réplica nativa do VoiceTextPopup (Flutter) para o Overlay. Sempre que a persona
// fala no Overlay e o toggle "Responder com texto" está ligado, mostra o texto num
// balão glass no topo da tela, sem depender do TTS (funciona com áudio OFF = modo
// só-leitura). Espelha o VoiceTextPopup do Home: topo abaixo da área do sistema,
// glass escuro + borda branca 12%, texto 15sp centralizado, duração 5s + 55ms/char
// com teto de 12s, fade in/out. Não intercepta toques nem cobre o botão flutuante.
object OverlayTextPopup {

    // WindowManager só pode ser tocado na main thread — todo show/remove é postado aqui.
    private val mainHandler = Handler(Looper.getMainLooper())

    // Estado atual — só um balão por vez. Uma fala nova substitui a anterior.
    private var windowManager: WindowManager? = null
    private var view: View? = null
    private var dismissRunnable: Runnable? = null

    // Exibe [text] no topo da tela. No-op se vazio. Sempre roda na main thread.
    fun show(context: Context, text: String) {
        val msg = text.trim()
        if (msg.isEmpty()) return
        val ctx = context.applicationContext
        mainHandler.post { render(ctx, msg) }
    }

    private fun render(ctx: Context, msg: String) {
        remove() // troca imediata: descarta o balão anterior

        // WindowManager associado ao display default (mesma razão do botão flutuante:
        // evita BadTokenException no addView em Android 11+).
        val wm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val display = ctx.getSystemService(DisplayManager::class.java)
                .getDisplay(Display.DEFAULT_DISPLAY)!!
            ctx.createWindowContext(display, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
                .getSystemService(Context.WINDOW_SERVICE) as WindowManager
        } else {
            ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }

        // Balão glass: fundo escuro translúcido (AppColors.backgroundElevated @ ~90%)
        // + borda branca 12% (mesma receita do GlassSurface), cantos 18dp.
        val bubble = GradientDrawable().apply {
            cornerRadius = dp(ctx, 18).toFloat()
            setColor(0xE60F1828.toInt())        // backgroundElevated ~90%
            setStroke(dp(ctx, 1), 0x1FFFFFFF)   // white 12%
        }

        val tv = TextView(ctx).apply {
            text = msg
            setTextColor(0xFFFFFFFF.toInt())    // textPrimary
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.3f)
            background = bubble
            setPadding(dp(ctx, 18), dp(ctx, 14), dp(ctx, 18), dp(ctx, 14))
            alpha = 0f // fade-in abaixo
        }
        view = tv
        windowManager = wm

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            ctx.resources.displayMetrics.widthPixels - dp(ctx, 40), // margens laterais 20dp
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            // Não focável e não tocável: só informativo, não intercepta toques da tela.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight(ctx) + dp(ctx, 16) // abaixo da área do sistema
        }

        // Blur real do fundo (glass) no Android 12+ — equivalente ao BackdropFilter do
        // GlassSurface. No-op visual em quem não suporta; nunca falha.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            params.blurBehindRadius = dp(ctx, 24)
        }

        try {
            wm.addView(tv, params)
            tv.animate().alpha(1f).setDuration(220).start() // fade-in
        } catch (_: Exception) {
            view = null; windowManager = null
            return
        }

        // Duração proporcional ao texto (5s + 55ms/char, teto 12s) — igual ao Home.
        val holdMs = (5000L + msg.length * 55L).coerceIn(5000L, 12000L)
        val dismiss = Runnable {
            view?.animate()?.alpha(0f)?.setDuration(220)?.withEndAction { remove() }?.start()
        }
        dismissRunnable = dismiss
        mainHandler.postDelayed(dismiss, holdMs)
    }

    // Remove o balão atual imediatamente (troca por fala nova ou fim da exibição).
    private fun remove() {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        dismissRunnable = null
        val v = view; val wm = windowManager
        if (v != null && wm != null) {
            try { wm.removeView(v) } catch (_: Exception) {}
        }
        view = null; windowManager = null
    }

    private fun dp(ctx: Context, v: Int): Int =
        (v * ctx.resources.displayMetrics.density + 0.5f).toInt()

    private fun statusBarHeight(ctx: Context): Int {
        val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) ctx.resources.getDimensionPixelSize(id) else dp(ctx, 24)
    }
}
