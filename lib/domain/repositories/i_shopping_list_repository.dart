import '../entities/shopping_list_item_entity.dart';

// Contrato do repositório da lista de compras (ambientes tipo Mercado).
abstract interface class IShoppingListRepository {
  // Observa em tempo real os itens de um mercado (para UI reativa)
  Stream<List<ShoppingListItemEntity>> watchByEnvironment(String environmentId);

  // Retorna apenas os itens NÃO marcados — usado ao montar a notificação
  Future<List<ShoppingListItemEntity>> getPendingByEnvironment(
    String environmentId,
  );

  // Insere um item (gera UUID se id vazio)
  Future<void> add(ShoppingListItemEntity item);

  // Remove um item pelo ID
  Future<void> delete(String id);

  // ÚNICO ponto que altera isChecked — UI e futuras ações (ex: notificação)
  // devem chamar só este método, nunca duplicar a lógica de marcar/desmarcar.
  Future<void> toggleChecked(String id, bool checked);

  // Remove todos os itens de um mercado (concluir compra)
  Future<void> deleteAllByEnvironment(String environmentId);
}
