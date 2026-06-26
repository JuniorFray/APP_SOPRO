import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/context_cards_table.dart';

// DAO para a tabela de ContextCards.
// Gerencia o perfil público do usuário que é trocado via BLE.
part 'context_cards_dao.g.dart';

@DriftAccessor(tables: [ContextCards])
class ContextCardsDao extends DatabaseAccessor<SoproDatabase>
    with _$ContextCardsDaoMixin {
  ContextCardsDao(super.db);

  // Retorna o cartão mais recentemente atualizado — considerado o cartão ativo
  Future<ContextCard?> findActive() =>
      (select(contextCards)
            ..orderBy([(c) => OrderingTerm(expression: c.updatedAt, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();

  // Observa o cartão ativo em tempo real (para a tela de edição de perfil)
  Stream<ContextCard?> watchActive() =>
      (select(contextCards)
            ..orderBy([(c) => OrderingTerm(expression: c.updatedAt, mode: OrderingMode.desc)])
            ..limit(1))
          .watchSingleOrNull();

  // Retorna todos os cartões — útil para histórico de versões do perfil
  Future<List<ContextCard>> findAll() =>
      (select(contextCards)
            ..orderBy([(c) => OrderingTerm(expression: c.updatedAt, mode: OrderingMode.desc)]))
          .get();

  // Insere ou atualiza um cartão
  Future<void> upsert(ContextCardsCompanion entry) =>
      into(contextCards).insertOnConflictUpdate(entry);

  // Remove um cartão pelo ID
  Future<int> deleteById(String id) =>
      (delete(contextCards)..where((c) => c.id.equals(id))).go();
}
