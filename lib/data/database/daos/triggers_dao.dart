import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/triggers_table.dart';

// DAO para a tabela de Triggers.
// Gerencia todas as operações de persistência dos gatilhos (intenções do usuário).
//
// Nota: o data class gerado se chama TriggerRow (não Trigger) para evitar
// conflito com a classe Trigger interna do Drift. Ver @DataClassName na tabela.
// O Companion gerado ainda se chama TriggersCompanion (derivado do nome da tabela).
part 'triggers_dao.g.dart';

@DriftAccessor(tables: [Triggers])
class TriggersDao extends DatabaseAccessor<SoproDatabase>
    with _$TriggersDaoMixin {
  TriggersDao(super.db);

  // Retorna todos os triggers de um ambiente específico, ativos primeiro
  Future<List<TriggerRow>> findByEnvironment(String environmentId) =>
      (select(triggers)
            ..where((t) => t.environmentId.equals(environmentId))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.isActive,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .get();

  // Observa em tempo real os triggers de um ambiente (para UI reativa)
  Stream<List<TriggerRow>> watchByEnvironment(String environmentId) =>
      (select(triggers)
            ..where((t) => t.environmentId.equals(environmentId))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.isActive,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  // Retorna apenas os triggers ativos de um ambiente — usado pelo geofence service
  Future<List<TriggerRow>> findActiveByEnvironment(String environmentId) =>
      (select(triggers)
            ..where(
              (t) =>
                  t.environmentId.equals(environmentId) &
                  t.isActive.equals(true),
            ))
          .get();

  // Insere ou atualiza um trigger
  Future<void> upsert(TriggersCompanion entry) =>
      into(triggers).insertOnConflictUpdate(entry);

  // Ativa ou desativa um trigger pelo ID
  Future<bool> setActive(String id, {required bool active}) =>
      (update(triggers)..where((t) => t.id.equals(id)))
          .write(TriggersCompanion(isActive: Value(active)))
          .then((count) => count > 0);

  // Remove um trigger pelo ID
  Future<int> deleteById(String id) =>
      (delete(triggers)..where((t) => t.id.equals(id))).go();
}
