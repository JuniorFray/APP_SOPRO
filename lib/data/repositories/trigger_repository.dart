import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/triggers_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/trigger_entity.dart';
import '../../domain/repositories/i_trigger_repository.dart';

// Implementação concreta do ITriggerRepository usando Drift (SQLite).
class TriggerRepository implements ITriggerRepository {
  final TriggersDao _dao;
  final _uuid = const Uuid();

  TriggerRepository(this._dao);

  @override
  Future<List<TriggerEntity>> getByEnvironment(String environmentId) async {
    final rows = await _dao.findByEnvironment(environmentId);
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<List<TriggerEntity>> watchByEnvironment(String environmentId) =>
      _dao
          .watchByEnvironment(environmentId)
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<TriggerEntity>> getActiveByEnvironment(
    String environmentId,
  ) async {
    final rows = await _dao.findActiveByEnvironment(environmentId);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> save(TriggerEntity entity) {
    final id = entity.id.isEmpty ? _uuid.v4() : entity.id;
    return _dao.upsert(
      TriggersCompanion(
        id: Value(id),
        environmentId: Value(entity.environmentId),
        title: Value(entity.title),
        content: Value(entity.content),
        isActive: Value(entity.isActive),
        createdAt: Value(entity.createdAt),
      ),
    );
  }

  @override
  Future<void> setActive(String id, {required bool active}) async {
    await _dao.setActive(id, active: active);
  }

  @override
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
  }

  TriggerEntity _toEntity(TriggerRow row) => TriggerEntity(
        id: row.id,
        environmentId: row.environmentId,
        title: row.title,
        content: row.content,
        isActive: row.isActive,
        createdAt: row.createdAt,
      );
}
