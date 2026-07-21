// Entidade pura de domínio para um item da lista de compras de um Mercado.
// Não depende de nenhuma biblioteca externa — só Dart puro (mesmo estilo de
// TriggerEntity). Vinculado a um Environment com isMarket == true.
class ShoppingListItemEntity {
  // Identificador único gerado via UUID v4
  final String id;

  // FK para o Environment (mercado) ao qual este item pertence
  final String environmentId;

  // Nome do item (ex: "Leite", "Pão")
  final String name;

  // Marcado como comprado; alterado somente via ShoppingListRepository.toggleChecked
  final bool isChecked;

  // Data de criação do registro (ordena a lista)
  final DateTime createdAt;

  const ShoppingListItemEntity({
    required this.id,
    required this.environmentId,
    required this.name,
    required this.isChecked,
    required this.createdAt,
  });
}
