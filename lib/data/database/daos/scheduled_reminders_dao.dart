import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/scheduled_reminders_table.dart';

// DAO para a tabela de lembretes com horário (independentes de ambiente).
// Concentra as queries SQL dos lembretes agendados.
//
// O data class gerado se chama ScheduledReminder; o Companion,
// ScheduledRemindersCompanion (derivado do nome da tabela).
part 'scheduled_reminders_dao.g.dart';

@DriftAccessor(tables: [ScheduledReminders])
class ScheduledRemindersDao extends DatabaseAccessor<SoproDatabase>
    with _$ScheduledRemindersDaoMixin {
  ScheduledRemindersDao(super.db);

  // Observa em tempo real todos os lembretes ativos (UI reativa),
  // ordenados pelo próximo disparo (scheduledAt ascendente).
  Stream<List<ScheduledReminder>> watchAllActive() =>
      (select(scheduledReminders)
            ..where((r) => r.isActive.equals(true))
            ..orderBy([(r) => OrderingTerm(expression: r.scheduledAt)]))
          .watch();

  // Observa o PRÓXIMO lembrete ativo (menor scheduledAt) — para o card
  // "Próximo lembrete" da Home. Reaproveita a ordenação de watchAllActive
  // e mapeia para o primeiro elemento (ou null se a lista estiver vazia).
  Stream<ScheduledReminder?> watchNext() =>
      watchAllActive().map((list) => list.isEmpty ? null : list.first);

  // Insere ou atualiza um lembrete (upsert por ID)
  Future<void> upsert(ScheduledRemindersCompanion entry) =>
      into(scheduledReminders).insertOnConflictUpdate(entry);

  // Ativa/pausa um lembrete pelo ID
  Future<bool> setActive(String id, {required bool active}) =>
      (update(scheduledReminders)..where((r) => r.id.equals(id)))
          .write(ScheduledRemindersCompanion(isActive: Value(active)))
          .then((count) => count > 0);

  // Atualiza o modo de alerta (notification/alarm/both) pelo ID
  Future<bool> updateAlertMode(String id, String mode) =>
      (update(scheduledReminders)..where((r) => r.id.equals(id)))
          .write(ScheduledRemindersCompanion(alertMode: Value(mode)))
          .then((count) => count > 0);

  // Remove um lembrete pelo ID
  Future<int> deleteById(String id) =>
      (delete(scheduledReminders)..where((r) => r.id.equals(id))).go();
}
