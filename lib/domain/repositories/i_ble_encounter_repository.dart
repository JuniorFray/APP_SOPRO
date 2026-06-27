import '../entities/ble_encounter_entity.dart';

// Contrato do repositório de encontros BLE.
// A implementação concreta usa Drift; esta interface permite substituí-la
// por um mock em testes sem afetar a camada de apresentação.
abstract class IBleEncounterRepository {
  // Insere ou atualiza um encontro (upsert via deviceId como chave)
  Future<void> save(BleEncounterEntity entity);

  // Stream de encontros em tempo real, ordenados do mais recente ao mais antigo
  Stream<List<BleEncounterEntity>> watchAll();

  // Remove o encontro com um dispositivo específico (privacidade)
  Future<void> delete(String deviceId);

  // Remove todos os encontros (limpeza completa de histórico)
  Future<void> deleteAll();
}
