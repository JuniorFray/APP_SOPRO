import 'package:flutter/services.dart';

import '../logging/core/logger.dart';

// Wrapper Dart para o MethodChannel "com.sopro.sopro/reminders".
// Delega o agendamento de alarmes exatos ao AlarmManager do Android — o
// ReminderReceiver.kt dispara a notificação no horário mesmo com o app morto.
//
// Mesmo estilo de NativeGeofenceService: métodos finos sobre o MethodChannel.
class ReminderScheduler {
  static const _channel = MethodChannel('com.sopro.sopro/reminders');

  // Agenda (ou reagenda) o disparo de [reminderId] em [triggerAtMillis]
  // (epoch em ms). Idempotente — chamar de novo com o mesmo ID atualiza.
  Future<void> scheduleReminder(String reminderId, int triggerAtMillis) async {
    try {
      await _channel.invokeMethod<void>('scheduleReminder', {
        'reminderId': reminderId,
        'triggerAtMillis': triggerAtMillis,
      });
    } catch (e) {
      Logger.warn('reminder_schedule_channel_failed',
          payload: {'reminder_id': reminderId, 'error': e.toString()},
          feature: 'reminders', action: 'scheduleReminder');
    }
  }

  // Cancela o alarme de [reminderId] (ao desativar ou deletar o lembrete).
  Future<void> cancelReminder(String reminderId) async {
    try {
      await _channel.invokeMethod<void>('cancelReminder', {
        'reminderId': reminderId,
      });
    } catch (e) {
      Logger.warn('reminder_cancel_channel_failed',
          payload: {'reminder_id': reminderId, 'error': e.toString()},
          feature: 'reminders', action: 'cancelReminder');
    }
  }

  // true se o app pode agendar alarmes exatos (canScheduleExactAlarms()).
  // Sempre true em Android < 12 (API < 31).
  Future<bool> hasExactAlarmPermission() async {
    return await _channel.invokeMethod<bool>('hasExactAlarmPermission') ?? true;
  }

  // Abre Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM para o usuário conceder
  // a permissão de alarme exato (Android 12+). No-op em versões anteriores.
  Future<void> openExactAlarmSettings() async {
    await _channel.invokeMethod<void>('openExactAlarmSettings');
  }
}
