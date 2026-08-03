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

  // Retorna os triggers visíveis de um ambiente (exclui tombstones), ativos primeiro
  Future<List<TriggerRow>> findByEnvironment(String environmentId) =>
      (select(triggers)
            ..where((t) =>
                t.environmentId.equals(environmentId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.isActive,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .get();

  // Observa em tempo real os triggers visíveis de um ambiente (UI reativa)
  Stream<List<TriggerRow>> watchByEnvironment(String environmentId) =>
      (select(triggers)
            ..where((t) =>
                t.environmentId.equals(environmentId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.isActive,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  // Retorna apenas os triggers ativos e visíveis de um ambiente — usado pelo geofence
  Future<List<TriggerRow>> findActiveByEnvironment(String environmentId) =>
      (select(triggers)
            ..where(
              (t) =>
                  t.environmentId.equals(environmentId) &
                  t.isActive.equals(true) &
                  t.deletedAt.isNull(),
            ))
          .get();

  // Insere ou atualiza um trigger. Carimba updatedAt=agora (escrita do app → sync).
  Future<void> upsert(TriggersCompanion entry) =>
      into(triggers).insertOnConflictUpdate(
          entry.copyWith(updatedAt: Value(DateTime.now())));

  // Ativa ou desativa um trigger pelo ID
  Future<bool> setActive(String id, {required bool active}) =>
      (update(triggers)..where((t) => t.id.equals(id)))
          .write(TriggersCompanion(
              isActive: Value(active), updatedAt: Value(DateTime.now())))
          .then((count) => count > 0);

  // Soft delete pelo ID: marca deletedAt (tombstone) em vez de remover a linha.
  Future<int> deleteById(String id) {
    final now = DateTime.now();
    return (update(triggers)..where((t) => t.id.equals(id)))
        .write(TriggersCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  // ── Motor de sync (Estágio 2.1) ────────────────────────────────────────────
  Future<List<TriggerRow>> allForSync() => select(triggers).get();

  Future<TriggerRow?> findByIdRaw(String id) =>
      (select(triggers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> applyRemote(TriggersCompanion entry) =>
      into(triggers).insertOnConflictUpdate(entry);
}
