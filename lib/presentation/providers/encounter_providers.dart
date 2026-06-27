import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/ble_encounter_entity.dart';
import 'database_provider.dart';

// Stream de encontros BLE em tempo real.
// Escuta mudanças no banco Drift e emite a lista atualizada automaticamente.
// Ordenado do mais recente ao mais antigo.
final encountersStreamProvider = StreamProvider<List<BleEncounterEntity>>((ref) {
  return ref.watch(bleEncounterRepositoryProvider).watchAll();
});
