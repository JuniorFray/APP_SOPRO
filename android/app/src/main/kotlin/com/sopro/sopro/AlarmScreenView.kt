package com.sopro.sopro

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

// AlarmScreenView — layout programático (sem XML) da tela de alarme: fundo
// escuro, título, conteúdo e botão grande "Parar". Extraído da antiga
// ReminderAlarmActivity para ser COMPARTILHADO entre ela (setContentView) e a
// ReminderAlarmOverlayService (WindowManager.addView) — visual idêntico nos dois
// caminhos. [onStop] é chamado ao tocar "Parar".
object AlarmScreenView {

    fun build(
        context: Context,
        title: String,
        content: String,
        onStop: () -> Unit,
    ): LinearLayout {
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0E0F13"))
            setPadding(48, 48, 48, 48)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        root.addView(TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 30f
            gravity = Gravity.CENTER
        })

        if (content.isNotEmpty()) {
            root.addView(TextView(context).apply {
                text = content
                setTextColor(Color.parseColor("#B9BCC6"))
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 24, 0, 0)
            })
        }

        root.addView(Button(context).apply {
            text = "Parar"
            textSize = 20f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#FF6B5B")) // accent coral
            setPadding(0, 32, 0, 32)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 64 }
            setOnClickListener { onStop() }
        })

        return root
    }
}
