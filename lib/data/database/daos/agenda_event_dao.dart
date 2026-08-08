import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/agenda_event_table.dart';

part 'agenda_event_dao.g.dart';

@DriftAccessor(tables: [AgendaEventTable])
class AgendaEventDao extends DatabaseAccessor<SoproDatabase> with _$AgendaEventDaoMixin {
  AgendaEventDao(super.db);

  Future<List<AgendaEventEntry>> getAllEvents() => select(agendaEventTable).get();

  Future<List<AgendaEventEntry>> getEventsInRange(int startMs, int endMs) {
    return (select(agendaEventTable)
          ..where((t) => t.startTime.isSmallerOrEqualValue(endMs) & t.endTime.isBiggerOrEqualValue(startMs)))
        .get();
  }

  Future<int> insertEvent(AgendaEventTableCompanion event) => into(agendaEventTable).insert(event);
  
  Future<bool> updateEvent(AgendaEventTableCompanion event) => update(agendaEventTable).replace(event);
  
  Future<int> deleteEvent(String id) => (delete(agendaEventTable)..where((t) => t.id.equals(id))).go();
}
