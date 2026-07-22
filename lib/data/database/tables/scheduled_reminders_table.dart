import 'package:drift/drift.dart';

// Definição da tabela "scheduled_reminders" no SQLite via Drift.
// Um lembrete por horário, independente de ambiente/geofence — ex.:
// "reunião hoje às 16h", "consulta dia 25 às 9h". Repetição opcional
// (diária ou semanal em dias específicos).
class ScheduledReminders extends Table {
  // UUID v4 como chave primária
  TextColumn get id => text()();

  // Título curto exibido na notificação
  TextColumn get title => text().withLength(min: 1, max: 200)();

  // Conteúdo/detalhe opcional do lembrete
  TextColumn get content => text().withDefault(const Constant(''))();

  // Data e hora do PRÓXIMO disparo (para lembretes recorrentes, este
  // campo é recalculado/avançado após cada disparo)
  DateTimeColumn get scheduledAt => dateTime()();

  // Regra de repetição: 'none' | 'daily' | 'weekly'
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();

  // Dias da semana para repeatRule == 'weekly', formato "1,3,5"
  // (1=segunda ... 7=domingo, ISO 8601). Vazio para 'none'/'daily'.
  TextColumn get repeatDaysOfWeek => text().withDefault(const Constant(''))();

  // Flag de ativação; 1 = ativo, 0 = pausado/concluído
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  // Modo de alerta ao disparar: 'notification' | 'alarm' | 'both'
  TextColumn get alertMode =>
      text().withDefault(const Constant('notification'))();

  // Timestamp de criação
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
