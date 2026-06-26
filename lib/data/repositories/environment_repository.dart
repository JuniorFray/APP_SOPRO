import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/environments_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/repositories/i_environment_repository.dart';

// Implementação concreta do IEnvironmentRepository usando Drift (SQLite).
// Responsável por converter entre o row do banco (Environment) e a
// entidade de domínio (EnvironmentEntity).
class EnvironmentRepository implements IEnvironmentRepository {
  final EnvironmentsDao _dao;

  // UUID v4 para geração de IDs quando a entidade não tiver um
  final _uuid = const Uuid();

  EnvironmentRepository(this._dao);

  @override
  Future<List<EnvironmentEntity>> getAll() async {
    final rows = await _dao.findAll();
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<List<EnvironmentEntity>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(_toEntity).toList());

  @override
  Future<EnvironmentEntity?> getById(String id) async {
    final row = await _dao.findById(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> save(EnvironmentEntity entity) {
    // Gera UUID se a entidade ainda não tiver ID (nova entidade)
    final id = entity.id.isEmpty ? _uuid.v4() : entity.id;
    return _dao.upsert(
      EnvironmentsCompanion(
        id: Value(id),
        name: Value(entity.name),
        latitude: Value(entity.latitude),
        longitude: Value(entity.longitude),
        radiusMeters: Value(entity.radiusMeters),
        createdAt: Value(entity.createdAt),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
  }

  // Converte o row do banco para a entidade pura de domínio
  EnvironmentEntity _toEntity(Environment row) => EnvironmentEntity(
        id: row.id,
        name: row.name,
        latitude: row.latitude,
        longitude: row.longitude,
        radiusMeters: row.radiusMeters,
        createdAt: row.createdAt,
      );
}
