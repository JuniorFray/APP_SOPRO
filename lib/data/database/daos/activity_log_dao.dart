import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/activity_log_table.dart';

// DAO para a tabela de histórico de atividades (seção "Atividade Recente").
// Concentra as queries SQL dos eventos visíveis ao usuário.
//
// O data class gerado se chama ActivityLogEntry; o Companion,
// ActivityLogEntriesCompanion (derivado do nome da tabela).
part 'activity_log_dao.g.dart';

@DriftAccessor(tables: [ActivityLogEntries])
class ActivityLogDao extends DatabaseAccessor<SoproDatabase>
    with _$ActivityLogDaoMixin {
  ActivityLogDao(super.db);

  // Observa em tempo real as atividades mais recentes (UI reativa),
  // mais novas primeiro (createdAt DESCENDENTE), limitado a [limit].
  Stream<List<ActivityLogEntry>> watchRecent({int limit = 20}) =>
      (select(activityLogEntries)
            ..orderBy([
              (e) => OrderingTerm(
                    expression: e.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .watch();

  // Insere uma nova entrada de atividade
  Future<void> insert(ActivityLogEntriesCompanion entry) =>
      into(activityLogEntries).insert(entry);

  // Remove entradas anteriores a [cutoff] — limpeza futura opcional.
  Future<int> deleteOlderThan(DateTime cutoff) =>
      (delete(activityLogEntries)..where((e) => e.createdAt.isSmallerThanValue(cutoff)))
          .go();
}
