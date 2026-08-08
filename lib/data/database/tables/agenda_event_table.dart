import 'package:drift/drift.dart';

@DataClassName('AgendaEventEntry')
class AgendaEventTable extends Table {
  TextColumn get id => text()(); // UUID of the event
  TextColumn get title => text().withLength(min: 1, max: 255)();
  TextColumn get description => text().nullable()();
  
  // Datas em SEGUNDOS desde epoch (mesma convenção Drift do resto do banco —
  // environments/triggers/reminders). Antes eram ms; a migração v20 converte.
  IntColumn get startTime => integer()();
  IntColumn get endTime => integer()();

  // e.g. "sopro", "ai_suggestion", "smart_import"
  TextColumn get source => text().withDefault(const Constant('sopro'))();

  // Categoria escolhida no formulário (Pessoal/Trabalho/Saúde/Sopro AI).
  TextColumn get category => text().nullable()();

  TextColumn get externalEventId => text().nullable()();
  TextColumn get calendarId => text().nullable()();

  // Soft delete (tombstone) em SEGUNDOS. Null = ativo. Alinha a Agenda ao
  // padrão das tabelas sincronizadas — evita re-trabalho quando entrar no sync.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
