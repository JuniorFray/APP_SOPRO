package com.sopro.sopro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.sopro.sopro.logging.Logger
import java.util.Calendar

// Agenda o alarme exato da notificação diária de clima. Mesmo padrão do
// ReminderScheduler, mas um único alarme fixo do sistema (requestCode fixo),
// SEM linha em scheduled_reminders. Reutilizado por MainActivity (canal),
// WeatherNotificationReceiver (reagenda pra amanhã) e BootReceiver (reboot).
object WeatherNotificationScheduler {

    // requestCode/notifId fixos deste alarme único.
    const val NOTIF_ID = 0x5750 // "WP" — id estável da notificação de clima
    private fun requestCode(): Int = "weather_daily".hashCode() and 0x7FFFFFFF

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    // Próximo horário: hoje se ainda não passou, senão amanhã.
    fun nextTriggerMillis(hour: Int, minute: Int): Long {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (!target.after(now)) target.add(Calendar.DAY_OF_MONTH, 1)
        return target.timeInMillis
    }

    fun schedule(context: Context, hour: Int, minute: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context, requestCode(),
            Intent(context, WeatherNotificationReceiver::class.java),
            pendingIntentFlags())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            Logger.warn("weather_schedule_denied", feature = "weather",
                action = "schedule")
            return
        }
        val at = nextTriggerMillis(hour, minute)
        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        Logger.info("weather_notification_scheduled", feature = "weather", action = "schedule",
            payload = mapOf("hour" to hour.toString(), "minute" to minute.toString(),
                "next_at_ms" to at.toString(), "next_at_s" to (at / 1000L).toString()))
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context, requestCode(),
            Intent(context, WeatherNotificationReceiver::class.java),
            pendingIntentFlags())
        am.cancel(pi)
        Logger.info("weather_notification_cancelled", feature = "weather", action = "cancel")
    }
}
