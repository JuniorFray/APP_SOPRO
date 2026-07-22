package com.sopro.sopro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.sopro.sopro.logging.Logger

// Utilitário de agendamento de alarmes exatos para lembretes.
// Chamado por três pontos:
//   - MethodChannel "com.sopro.sopro/reminders" (Dart pedindo pra agendar/cancelar)
//   - ReminderReceiver (reagenda recorrentes após o disparo)
//   - BootReceiver (reagenda lembretes ativos após reboot — alarmes exatos são
//     descartados pelo Android no reboot, igual aos geofences)
//
// Sem Flutter Engine — código Android puro.
object ReminderScheduler {

    // requestCode do PendingIntent = hash positivo do reminderId, mesmo padrão do
    // notification ID usado no resto do projeto (id.hashCode() and 0x7FFFFFFF).
    private fun requestCodeFor(reminderId: String): Int =
        reminderId.hashCode() and 0x7FFFFFFF

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    // Agenda (ou reagenda) um alarme exato que dispara o ReminderReceiver no
    // horário [triggerAtMillis]. No Android 12+ exige canScheduleExactAlarms().
    fun scheduleExact(context: Context, reminderId: String, triggerAtMillis: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra("reminder_id", reminderId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCodeFor(reminderId), intent, pendingIntentFlags())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()) {
            Logger.warn("reminder_schedule_denied", feature = "reminders",
                action = "scheduleExact", payload = mapOf("reminder_id" to reminderId))
            return
        }
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        Logger.info("reminder_scheduled", feature = "reminders", action = "scheduleExact",
            payload = mapOf("reminder_id" to reminderId, "trigger_at" to triggerAtMillis.toString()))
    }

    // Cancela o alarme de um lembrete (mesmo requestCode/flags do agendamento).
    fun cancel(context: Context, reminderId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCodeFor(reminderId),
            Intent(context, ReminderReceiver::class.java), pendingIntentFlags())
        alarmManager.cancel(pendingIntent)
        Logger.info("reminder_cancelled", feature = "reminders", action = "cancel",
            payload = mapOf("reminder_id" to reminderId))
    }
}
