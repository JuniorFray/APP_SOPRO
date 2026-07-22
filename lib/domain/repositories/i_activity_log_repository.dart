import '../entities/activity_log_entry_entity.dart';

// Contrato do repositório do histórico de atividades ("Atividade Recente").
abstract interface class IActivityLogRepository {
  // Observa em tempo real as atividades mais recentes (para UI reativa)
  Stream<List<ActivityLogEntryEntity>> watchRecent({int limit = 20});

  // Registra uma atividade — método único e simples para os pontos de
  // instrumentação. Gera UUID e createdAt=DateTime.now() internamente.
  Future<void> log({
    required ActivityType type,
    required String title,
    String subtitle = '',
    String? environmentId,
  });
}
