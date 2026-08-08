import 'package:drift/drift.dart';

@DataClassName('AgendaEventEntry')
class AgendaEventTable extends Table {
  TextColumn get id => text()(); // UUID of the event
  TextColumn get title => text().withLength(min: 1, max: 255)();
  TextColumn get description => text().nullable()();
  
  // Storing dates as millisecondsSinceEpoch
  IntColumn get startTime => integer()();
  IntColumn get endTime => integer()();
  
  // e.g. "sopro", "ai_suggestion", "smart_import"
  TextColumn get source => text().withDefault(const Constant('sopro'))();
  
  TextColumn get externalEventId => text().nullable()();
  TextColumn get calendarId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
