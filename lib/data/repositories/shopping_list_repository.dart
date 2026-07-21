import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/shopping_list_items_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/shopping_list_item_entity.dart';
import '../../domain/repositories/i_shopping_list_repository.dart';

// Implementação concreta do IShoppingListRepository usando Drift (SQLite).
// Converte entre o row do banco (ShoppingListItem) e a entidade de domínio.
class ShoppingListRepository implements IShoppingListRepository {
  final ShoppingListItemsDao _dao;
  final _uuid = const Uuid();

  ShoppingListRepository(this._dao);

  @override
  Stream<List<ShoppingListItemEntity>> watchByEnvironment(
    String environmentId,
  ) =>
      _dao
          .watchByEnvironment(environmentId)
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<ShoppingListItemEntity>> getPendingByEnvironment(
    String environmentId,
  ) async {
    final rows = await _dao.findPendingByEnvironment(environmentId);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> add(ShoppingListItemEntity item) {
    final id = item.id.isEmpty ? _uuid.v4() : item.id;
    return _dao.upsert(
      ShoppingListItemsCompanion(
        id: Value(id),
        environmentId: Value(item.environmentId),
        name: Value(item.name),
        isChecked: Value(item.isChecked),
        createdAt: Value(item.createdAt),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
  }

  @override
  Future<void> toggleChecked(String id, bool checked) async {
    // Único ponto que altera isChecked no app.
    await _dao.setChecked(id, checked: checked);
  }

  @override
  Future<void> deleteAllByEnvironment(String environmentId) async {
    await _dao.deleteAllByEnvironment(environmentId);
  }

  ShoppingListItemEntity _toEntity(ShoppingListItem row) =>
      ShoppingListItemEntity(
        id: row.id,
        environmentId: row.environmentId,
        name: row.name,
        isChecked: row.isChecked,
        createdAt: row.createdAt,
      );
}
