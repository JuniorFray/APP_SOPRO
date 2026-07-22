// Regra de repetição de um lembrete agendado.
// Persistida como string ('none' | 'daily' | 'weekly') — a conversão
// de/para esta string fica no ScheduledReminderRepository.
enum ReminderRepeatRule { none, daily, weekly }

// Modo de alerta ao disparar o lembrete. Persistido como string
// ('notification' | 'alarm' | 'both'), mesma conversão do repeatRule.
//   notification → notificação padrão
//   alarm        → tela cheia + som (respeita silencioso), notificação discreta
//   both         → notificação padrão + tela de alarme
enum ReminderAlertMode { notification, alarm, both }

// Entidade pura de domínio para um Lembrete com horário (independente de
// ambiente/geofence). Dart puro, mesmo estilo de TriggerEntity.
// Ex.: "reunião hoje às 16h", "consulta dia 25 às 9h".
class ScheduledReminderEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // Título curto exibido na notificação
  final String title;

  // Conteúdo/detalhe opcional do lembrete
  final String content;

  // Data e hora do próximo disparo
  final DateTime scheduledAt;

  // Regra de repetição (none/daily/weekly)
  final ReminderRepeatRule repeatRule;

  // Dias da semana para repeatRule == weekly (1=segunda ... 7=domingo, ISO 8601).
  // Vazio para none/daily. Serializado como "1,3,5" no banco.
  final List<int> repeatDaysOfWeek;

  // Ativo (true) ou pausado/concluído (false)
  final bool isActive;

  // Modo de alerta ao disparar (notification/alarm/both)
  final ReminderAlertMode alertMode;

  // Data de criação do registro
  final DateTime createdAt;

  const ScheduledReminderEntity({
    required this.id,
    required this.title,
    required this.content,
    required this.scheduledAt,
    required this.repeatRule,
    required this.repeatDaysOfWeek,
    required this.isActive,
    this.alertMode = ReminderAlertMode.notification,
    required this.createdAt,
  });
}
