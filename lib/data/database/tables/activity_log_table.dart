import 'package:drift/drift.dart';

// Definição da tabela "activity_log" no SQLite via Drift.
// Histórico de eventos relevantes para o usuário, exibido na seção
// "Atividade Recente" da Home. Não confundir com AppLogger (telemetria
// interna para Supabase) — esta tabela é conteúdo visível ao usuário.
class ActivityLogEntries extends Table {
  TextColumn get id => text()();

  // Tipo do evento: 'environment_entered' | 'trigger_fired' |
  // 'reminder_completed' | 'shopping_completed' (futuro)
  TextColumn get type => text()();

  // Texto principal exibido (ex.: "Entrou em Casa", "Lembrete concluído")
  TextColumn get title => text()();

  // Texto secundário opcional (ex.: "Raio de 150m", "Levar guarda-chuva")
  TextColumn get subtitle => text().withDefault(const Constant(''))();

  // FK lógica opcional para o ambiente relacionado (sem cascade)
  TextColumn get environmentId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
