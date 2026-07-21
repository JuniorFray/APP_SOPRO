import '../entities/environment_entity.dart';

// Contrato (interface) do repositório de Environments.
// A camada de domínio depende desta abstração, nunca da implementação concreta.
// Isso permite trocar o banco (ex: migrar para SQLCipher) sem tocar no domínio.
abstract interface class IEnvironmentRepository {
  // Retorna todos os environments (consulta única)
  Future<List<EnvironmentEntity>> getAll();

  // Observa mudanças em tempo real — use com StreamProvider no Riverpod
  Stream<List<EnvironmentEntity>> watchAll();

  // Busca um environment pelo ID; null se não existir
  Future<EnvironmentEntity?> getById(String id);

  // Insere ou atualiza um environment (upsert por ID)
  Future<void> save(EnvironmentEntity entity);

  // Remove um environment e seus triggers em cascade
  Future<void> delete(String id);

  // Atualiza somente a flag isMarket (corrigir tipo do ambiente a qualquer momento)
  Future<void> updateIsMarket(String id, {required bool isMarket});
}
