import 'package:drift/drift.dart';

import '../database/daos/ble_encounters_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/ble_encounter_entity.dart';
import '../../domain/repositories/i_ble_encounter_repository.dart';

// Implementação concreta do IBleEncounterRepository usando Drift (SQLite).
class BleEncounterRepository implements IBleEncounterRepository {
  final BleEncountersDao _dao;

  BleEncounterRepository(this._dao);

  @override
  Future<void> save(BleEncounterEntity entity) => _dao.upsert(
        BleEncountersCompanion(
          deviceId:     Value(entity.deviceId),
          displayName:  Value(entity.displayName),
          role:         Value(entity.role),
          company:      Value(entity.company),
          bio:          Value(entity.bio),
          tags:         Value(entity.tags),
          encounteredAt: Value(entity.encounteredAt),
        ),
      );

  @override
  Stream<List<BleEncounterEntity>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map(_toEntity).toList());

  @override
  Future<void> delete(String deviceId) async =>
      await _dao.deleteByDeviceId(deviceId);

  @override
  Future<void> deleteAll() async => await _dao.deleteAll();

  BleEncounterEntity _toEntity(BleEncounter row) => BleEncounterEntity(
        deviceId:     row.deviceId,
        displayName:  row.displayName,
        role:         row.role,
        company:      row.company,
        bio:          row.bio,
        tags:         row.tags,
        encounteredAt: row.encounteredAt,
      );
}
