// Tipo de evento registrado no histórico de atividades.
// Persistido como string ('environment_entered' | 'trigger_fired' |
// 'reminder_completed' | 'shopping_completed') — a conversão de/para essa
// string fica no ActivityLogRepository (mesmo padrão de ReminderRepeatRule).
enum ActivityType {
  environmentEntered,
  triggerFired,
  reminderCompleted,
  shoppingCompleted,
}

// Entidade pura de domínio para uma entrada do histórico de atividades
// (seção "Atividade Recente" da Home). Dart puro, mesmo estilo de TriggerEntity.
class ActivityLogEntryEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // Tipo do evento
  final ActivityType type;

  // Texto principal exibido (ex.: "Entrou em Casa")
  final String title;

  // Texto secundário opcional (ex.: "Raio de 150m")
  final String subtitle;

  // ID do ambiente relacionado (null quando não se aplica)
  final String? environmentId;

  // Data de criação do registro (ordena o histórico)
  final DateTime createdAt;

  const ActivityLogEntryEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.environmentId,
    required this.createdAt,
  });
}
