import '../entities/scheduled_reminder_entity.dart';

// Contrato do repositório de lembretes com horário (independentes de ambiente).
abstract interface class IScheduledReminderRepository {
  // Observa em tempo real todos os lembretes ativos (para UI reativa)
  Stream<List<ScheduledReminderEntity>> watchAllActive();

  // Observa o próximo lembrete ativo (menor scheduledAt) — card da Home
  Stream<ScheduledReminderEntity?> watchNext();

  // Insere ou atualiza um lembrete (gera UUID se id vazio)
  Future<void> upsert(ScheduledReminderEntity reminder);

  // Ativa/pausa um lembrete pelo ID
  Future<void> setActive(String id, bool active);

  // Altera o modo de alerta (notification/alarm/both) pelo ID
  Future<void> updateAlertMode(String id, ReminderAlertMode mode);

  // Remove um lembrete pelo ID
  Future<void> delete(String id);
}
