import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/agenda_event_table.dart';

part 'agenda_event_dao.g.dart';

@DriftAccessor(tables: [AgendaEventTable])
class AgendaEventDao extends DatabaseAccessor<SoproDatabase> with _$AgendaEventDaoMixin {
  AgendaEventDao(super.db);

  // Leituras filtram tombstones (deletedAt IS NULL) — evento soft-deletado some.
  Future<List<AgendaEventEntry>> getAllEvents() =>
      (select(agendaEventTable)..where((t) => t.deletedAt.isNull())).get();

  // Janela em SEGUNDOS (mesma unidade que passou a ser gravada). Só ativos.
  Future<List<AgendaEventEntry>> getEventsInRange(int startSec, int endSec) {
    return (select(agendaEventTable)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.startTime.isSmallerOrEqualValue(endSec) &
              t.endTime.isBiggerOrEqualValue(startSec)))
        .get();
  }

  Future<int> insertEvent(AgendaEventTableCompanion event) => into(agendaEventTable).insert(event);

  Future<bool> updateEvent(AgendaEventTableCompanion event) => update(agendaEventTable).replace(event);

  // Soft delete: carimba deletedAt (segundos) em vez de remover a linha. Mantém o
  // tombstone para futura sincronização/compartilhamento.
  Future<int> deleteEvent(String id) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (update(agendaEventTable)..where((t) => t.id.equals(id)))
        .write(AgendaEventTableCompanion(deletedAt: Value(nowSec)));
  }
}
