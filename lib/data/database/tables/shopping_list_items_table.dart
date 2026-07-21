import 'package:drift/drift.dart';

// Definição da tabela "shopping_list_items" no SQLite via Drift.
// Cada linha é um item da lista de compras de um ambiente marcado como Mercado
// (Environments.isMarket == true). Substitui os gatilhos de texto nesses locais.
class ShoppingListItems extends Table {
  // UUID v4 como chave primária
  TextColumn get id => text()();

  // FK lógica para a tabela environments (sem cascade — limpeza via
  // ShoppingListRepository.deleteAllByEnvironment ao concluir a compra)
  TextColumn get environmentId => text()();

  // Nome do item digitado/falado pelo usuário
  TextColumn get name => text().withLength(min: 1, max: 200)();

  // Marcado (comprado) ou não; único ponto de alteração: toggleChecked
  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();

  // Timestamp de criação (ordena a lista por ordem de inserção)
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
