import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/context_cards_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/context_card_entity.dart';
import '../../domain/repositories/i_context_card_repository.dart';

// Implementação concreta do IContextCardRepository usando Drift (SQLite).
class ContextCardRepository implements IContextCardRepository {
  final ContextCardsDao _dao;
  final _uuid = const Uuid();

  ContextCardRepository(this._dao);

  @override
  Future<ContextCardEntity?> getActive() async {
    final row = await _dao.findActive();
    return row == null ? null : _toEntity(row);
  }

  @override
  Stream<ContextCardEntity?> watchActive() =>
      _dao.watchActive().map((row) => row == null ? null : _toEntity(row));

  @override
  Future<void> save(ContextCardEntity entity) {
    final id = entity.id.isEmpty ? _uuid.v4() : entity.id;
    // updatedAt é sempre atualizado para DateTime.now() em cada save,
    // garantindo que o receptor BLE possa detectar versões mais recentes
    return _dao.upsert(
      ContextCardsCompanion(
        id: Value(id),
        displayName: Value(entity.displayName),
        bio: Value(entity.bio),
        tags: Value(entity.tags),
        createdAt: Value(entity.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
  }

  ContextCardEntity _toEntity(ContextCard row) => ContextCardEntity(
        id: row.id,
        displayName: row.displayName,
        bio: row.bio,
        tags: row.tags,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
