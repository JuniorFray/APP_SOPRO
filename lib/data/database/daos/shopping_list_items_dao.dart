import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/shopping_list_items_table.dart';

// DAO para a tabela de itens de lista de compras.
// Concentra as queries SQL dos itens de mercado (ambientes com isMarket == true).
//
// O data class gerado se chama ShoppingListItem; o Companion,
// ShoppingListItemsCompanion (derivado do nome da tabela).
part 'shopping_list_items_dao.g.dart';

@DriftAccessor(tables: [ShoppingListItems])
class ShoppingListItemsDao extends DatabaseAccessor<SoproDatabase>
    with _$ShoppingListItemsDaoMixin {
  ShoppingListItemsDao(super.db);

  // Observa em tempo real os itens de um ambiente (UI reativa). Não marcados
  // primeiro, marcados no fim (isChecked false<true no SQLite); dentro de cada
  // grupo, mais antigos primeiro (ordem de inserção). toggleChecked reordena
  // sozinho — o stream reemite a lista já ordenada.
  Stream<List<ShoppingListItem>> watchByEnvironment(String environmentId) =>
      (select(shoppingListItems)
            ..where((i) => i.environmentId.equals(environmentId))
            ..orderBy([
              (i) => OrderingTerm(expression: i.isChecked),
              (i) => OrderingTerm(expression: i.createdAt),
            ]))
          .watch();

  // Retorna apenas os itens NÃO marcados de um ambiente — usado ao montar a
  // notificação de lista de compras ao entrar no geofence.
  Future<List<ShoppingListItem>> findPendingByEnvironment(
    String environmentId,
  ) =>
      (select(shoppingListItems)
            ..where(
              (i) =>
                  i.environmentId.equals(environmentId) &
                  i.isChecked.equals(false),
            )
            ..orderBy([(i) => OrderingTerm(expression: i.createdAt)]))
          .get();

  // Insere ou atualiza um item (upsert por ID)
  Future<void> upsert(ShoppingListItemsCompanion entry) =>
      into(shoppingListItems).insertOnConflictUpdate(entry);

  // Marca/desmarca um item pelo ID — único ponto que altera isChecked
  Future<bool> setChecked(String id, {required bool checked}) =>
      (update(shoppingListItems)..where((i) => i.id.equals(id)))
          .write(ShoppingListItemsCompanion(isChecked: Value(checked)))
          .then((count) => count > 0);

  // Remove um item pelo ID
  Future<int> deleteById(String id) =>
      (delete(shoppingListItems)..where((i) => i.id.equals(id))).go();

  // Remove todos os itens de um ambiente (concluir compra)
  Future<int> deleteAllByEnvironment(String environmentId) =>
      (delete(shoppingListItems)..where((i) => i.environmentId.equals(environmentId)))
          .go();
}
