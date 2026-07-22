package com.sopro.sopro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.SessionManager
import java.io.File
import java.util.Calendar
import java.util.concurrent.Executors

// BroadcastReceiver acionado pelo AlarmManager no horário exato de um lembrete
// agendado (ReminderScheduler.scheduleExact) — funciona com o app fechado/morto.
//
// Fluxo dentro de onReceive():
//   1. Extrai "reminder_id" do Intent.
//   2. Em thread de I/O: abre o banco (READWRITE), lê o lembrete ATIVO.
//      Se não existir (deletado/desativado entre agendar e disparar): não faz nada.
//   3. Exibe a notificação no mesmo canal das notificações de trigger.
//   4. repeat_rule:
//        'none'   → UPDATE is_active = 0 (consome a si mesmo).
//        'daily'  → scheduled_at += 24h, UPDATE + reagenda.
//        'weekly' → próximo dia válido de repeat_days_of_week (ISO 1..7),
//                   preservando hora:minuto, UPDATE + reagenda.
//   5. pendingResult.finish() no finally (mesmo padrão do BootReceiver).
//
// Sem Flutter Engine — código Android puro.
class ReminderReceiver : BroadcastReceiver() {

    companion object {
        // Reaproveita o canal das notificações de trigger (NotificationService.dart:
        // _triggerChannelId = 'sopro_triggers', IMPORTANCE_MAX). Divergência de ID
        // faria o notify() ser descartado silenciosamente pelo Android.
        private const val CHANNEL_ID   = "sopro_triggers"
        private const val CHANNEL_NAME = "Sopro — Gatilhos"

        private const val DAY_MS = 24L * 60L * 60L * 1000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        SessionManager.init(context)
        val receiverStart = System.currentTimeMillis()
        val corrId = CorrelationManager.beginOperation("reminder_event")

        val reminderId = intent.getStringExtra("reminder_id")
        if (reminderId == null) {
            Logger.warn("reminder_id_missing", feature = "reminders", action = "onReceive",
                correlationId = corrId)
            CorrelationManager.endOperation("reminder_event")
            return
        }

        Logger.info("reminder_alarm_received", feature = "reminders", action = "onReceive",
            correlationId = corrId, payload = mapOf("reminder_id" to reminderId))

        // goAsync(): trabalho de I/O fora do main thread sem o processo ser morto.
        val pendingResult = goAsync()
        Executors.newSingleThreadExecutor().execute {
            try {
                processReminder(context, reminderId, corrId)
                Logger.info("receiver_finished", feature = "reminders", action = "onReceive",
                    correlationId = corrId,
                    durationMs = System.currentTimeMillis() - receiverStart,
                    payload = mapOf("reminder_id" to reminderId))
            } catch (e: Exception) {
                Logger.error("reminder_process_failed", feature = "reminders", action = "onReceive",
                    correlationId = corrId, exception = e,
                    durationMs = System.currentTimeMillis() - receiverStart)
            } finally {
                CorrelationManager.endOperation("reminder_event")
                pendingResult.finish()
            }
        }
    }

    // Lê o lembrete ativo, notifica e aplica a regra de repetição (tudo num único
    // handle READWRITE). Padrão obrigatório do projeto: var db + finally close.
    private fun processReminder(context: Context, reminderId: String, corrId: String) {
        val candidates = listOf(
            File(context.filesDir.parentFile, "app_flutter/sopro.db"),
            File(context.filesDir, "sopro.db"),
            context.getDatabasePath("sopro.db"),
        )
        val dbFile = candidates.firstOrNull { it.exists() } ?: run {
            Logger.warn("sqlite_db_not_found", feature = "reminders",
                action = "processReminder", correlationId = corrId,
                payload = mapOf("reminder_id" to reminderId))
            return
        }

        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)

            var title = ""
            var content = ""
            var repeatRule = "none"
            var repeatDays = ""
            var alertMode = "notification"  // notification | alarm | both
            // Drift grava DateTime como epoch em SEGUNDOS (sem storeDateTimeAsText).
            // Convertido para MILISSEGUNDOS logo na leitura — daqui pra frente tudo
            // trabalha em millis (AlarmManager/RTC_WAKEUP espera millis).
            var scheduledAtMillis = 0L
            db.rawQuery(
                "SELECT title, content, repeat_rule, repeat_days_of_week, scheduled_at, alert_mode " +
                "FROM scheduled_reminders WHERE id = ? AND is_active = 1 LIMIT 1",
                arrayOf(reminderId)
            ).use { cursor ->
                if (!cursor.moveToFirst()) {
                    // Deletado ou desativado entre o agendamento e o disparo — ignora.
                    Logger.info("reminder_not_found_or_inactive", feature = "reminders",
                        action = "processReminder", correlationId = corrId,
                        payload = mapOf("reminder_id" to reminderId))
                    return
                }
                title       = cursor.getString(0) ?: ""
                content     = cursor.getString(1) ?: ""
                repeatRule  = cursor.getString(2) ?: "none"
                repeatDays  = cursor.getString(3) ?: ""
                scheduledAtMillis = cursor.getLong(4) * 1000L  // segundos → millis
                alertMode   = cursor.getString(5) ?: "notification"
            }

            showNotification(context, reminderId, title, content, alertMode, corrId)

            // ── Regra de repetição ──────────────────────────────────────────────
            when (repeatRule) {
                "daily" -> {
                    // Cálculo em millis; grava de volta em SEGUNDOS (Drift lê como segundos).
                    val nextMillis  = scheduledAtMillis + DAY_MS
                    val nextSeconds = nextMillis / 1000L
                    db.execSQL(
                        "UPDATE scheduled_reminders SET scheduled_at = ? WHERE id = ?",
                        arrayOf<Any>(nextSeconds, reminderId))
                    ReminderScheduler.scheduleExact(context, reminderId, nextMillis)
                    Logger.info("reminder_repeat_advanced", feature = "reminders",
                        action = "processReminder", correlationId = corrId,
                        payload = mapOf("reminder_id" to reminderId, "rule" to "daily",
                            "next_at_ms" to nextMillis.toString(),
                            "next_at_s" to nextSeconds.toString()))
                }
                "weekly" -> {
                    // Base em millis; grava de volta em SEGUNDOS (Drift lê como segundos).
                    val nextMillis  = nextWeeklyMillis(scheduledAtMillis, repeatDays)
                    val nextSeconds = nextMillis / 1000L
                    db.execSQL(
                        "UPDATE scheduled_reminders SET scheduled_at = ? WHERE id = ?",
                        arrayOf<Any>(nextSeconds, reminderId))
                    ReminderScheduler.scheduleExact(context, reminderId, nextMillis)
                    Logger.info("reminder_repeat_advanced", feature = "reminders",
                        action = "processReminder", correlationId = corrId,
                        payload = mapOf("reminder_id" to reminderId, "rule" to "weekly",
                            "next_at_ms" to nextMillis.toString(),
                            "next_at_s" to nextSeconds.toString()))
                }
                else -> {
                    // 'none': o lembrete consome a si mesmo.
                    db.execSQL(
                        "UPDATE scheduled_reminders SET is_active = 0 WHERE id = ?",
                        arrayOf(reminderId))
                    Logger.info("reminder_consumed", feature = "reminders",
                        action = "processReminder", correlationId = corrId,
                        payload = mapOf("reminder_id" to reminderId))
                }
            }
        } catch (e: Exception) {
            Logger.error("sqlite_reminder_failed", feature = "reminders",
                action = "processReminder", correlationId = corrId, exception = e,
                payload = mapOf("reminder_id" to reminderId))
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    // Calcula o próximo disparo semanal a partir de [scheduledAtMillis] (millis),
    // preservando hora:minuto, no próximo dia da semana presente em [daysCsv]
    // ("1,3,5", ISO 1=segunda..7=domingo). Retorna millis. Fallback +24h.
    private fun nextWeeklyMillis(scheduledAtMillis: Long, daysCsv: String): Long {
        val days = daysCsv.split(",")
            .mapNotNull { it.trim().toIntOrNull() }
            .filter { it in 1..7 }
            .toSet()
        if (days.isEmpty()) return scheduledAtMillis + DAY_MS

        val cal = Calendar.getInstance().apply { timeInMillis = scheduledAtMillis }
        // Avança de 1 a 7 dias até cair num dia válido (mantém hora:minuto:seg).
        for (i in 1..7) {
            cal.add(Calendar.DAY_OF_MONTH, 1)
            // Calendar: SUNDAY=1..SATURDAY=7 → ISO: MONDAY=1..SUNDAY=7.
            val iso = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (iso in days) break
        }
        return cal.timeInMillis
    }

    // Exibe a notificação do lembrete no canal 'sopro_triggers' (IMPORTANCE_MAX).
    // Cria o canal se ainda não existir (app nunca aberto). ID da notificação =
    // mesmo hash usado no requestCode do alarme.
    // [alertMode] = notification | alarm | both. Em 'alarm'/'both' anexa um
    // fullScreenIntent que abre a ReminderAlarmActivity (tela cheia + som).
    private fun showNotification(
        context: Context, reminderId: String, title: String, content: String,
        alertMode: String, corrId: String
    ) {
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            Logger.warn("notification_permission_denied", feature = "reminders",
                action = "showNotification", correlationId = corrId,
                payload = mapOf("reminder_id" to reminderId))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_MAX
                ).apply {
                    enableVibration(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(channel)
            }
        }

        val notifTitle = if (title.isNotEmpty()) title else "Lembrete"
        val notifBody  = if (content.isNotEmpty()) content else "Está na hora do seu lembrete."
        val notifId    = reminderId.hashCode() and 0x7FFFFFFF
        val wantsAlarm = alertMode == "alarm" || alertMode == "both"

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle(notifTitle)
            .setContentText(notifBody)
            .setTicker(notifTitle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)

        // Modo alarme: fullScreenIntent abre a Activity de tela cheia (quando a
        // tela está bloqueada/desligada) e mostra a notificação normal caso
        // contrário. setCategory(ALARM) reforça a prioridade do sistema.
        if (wantsAlarm) {
            val alarmIntent = Intent(context, ReminderAlarmActivity::class.java).apply {
                putExtra("title", notifTitle)
                putExtra("content", notifBody)
                putExtra("notif_id", notifId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY
            }
            val fullScreenPendingIntent = PendingIntent.getActivity(
                context, notifId, alarmIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(fullScreenPendingIntent, true)
        }

        val notification = builder.build()

        try {
            nmCompat.notify(notifId, notification)
            Logger.info("reminder_notification_sent", feature = "reminders",
                action = "showNotification", correlationId = corrId,
                payload = mapOf("reminder_id" to reminderId, "notification_id" to notifId.toString()))
        } catch (e: SecurityException) {
            Logger.error("reminder_notification_failed", feature = "reminders",
                action = "showNotification", correlationId = corrId, exception = e,
                payload = mapOf("reminder_id" to reminderId))
        }
    }
}
