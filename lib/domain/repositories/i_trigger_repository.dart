import '../entities/trigger_entity.dart';

// Contrato do repositório de Triggers.
abstract interface class ITriggerRepository {
  // Retorna todos os triggers de um ambiente
  Future<List<TriggerEntity>> getByEnvironment(String environmentId);

  // Observa triggers de um ambiente em tempo real
  Stream<List<TriggerEntity>> watchByEnvironment(String environmentId);

  // Retorna apenas os triggers ativos — usado pelo geofence service ao disparar
  Future<List<TriggerEntity>> getActiveByEnvironment(String environmentId);

  // Insere ou atualiza um trigger
  Future<void> save(TriggerEntity entity);

  // Ativa ou desativa um trigger sem sobrescrever os outros campos
  Future<void> setActive(String id, {required bool active});

  // Remove um trigger pelo ID
  Future<void> delete(String id);
}
