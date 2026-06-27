import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/ble_encounters_table.dart';

// DAO para a tabela de encontros BLE.
// Expõe queries de leitura/escrita sem que a camada de domínio
// precise conhecer Drift ou SQL.
part 'ble_encounters_dao.g.dart';

@DriftAccessor(tables: [BleEncounters])
class BleEncountersDao extends DatabaseAccessor<SoproDatabase>
    with _$BleEncountersDaoMixin {
  BleEncountersDao(super.db);

  // Upsert: se o deviceId já existir, atualiza todos os campos
  Future<void> upsert(BleEncountersCompanion entry) =>
      into(bleEncounters).insertOnConflictUpdate(entry);

  // Stream de todos os encontros, do mais recente ao mais antigo
  Stream<List<BleEncounter>> watchAll() =>
      (select(bleEncounters)
            ..orderBy([
              (e) => OrderingTerm(
                    expression: e.encounteredAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  // Lista estática (snapshot sem stream)
  Future<List<BleEncounter>> findAll() =>
      (select(bleEncounters)
            ..orderBy([
              (e) => OrderingTerm(
                    expression: e.encounteredAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .get();

  // Remove um encontro pelo endereço MAC
  Future<int> deleteByDeviceId(String deviceId) =>
      (delete(bleEncounters)..where((e) => e.deviceId.equals(deviceId))).go();

  // Limpa todo o histórico
  Future<int> deleteAll() => delete(bleEncounters).go();
}
