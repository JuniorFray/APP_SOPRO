import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/sopro_database.dart';
import '../../data/repositories/ble_encounter_repository.dart';
import '../../data/repositories/context_card_repository.dart';
import '../../data/repositories/environment_repository.dart';
import '../../data/repositories/trigger_repository.dart';
import '../../domain/repositories/i_ble_encounter_repository.dart';
import '../../domain/repositories/i_context_card_repository.dart';
import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/repositories/i_trigger_repository.dart';

// Provider do banco de dados principal.
// Criado uma única vez e fechado quando o ProviderScope for destruído.
final databaseProvider = Provider<SoproDatabase>((ref) {
  final db = SoproDatabase();
  ref.onDispose(db.close);
  return db;
});

// Providers dos repositórios — expõem as interfaces (não as implementações)
// para que a camada de apresentação não dependa de Drift diretamente.

final environmentRepositoryProvider = Provider<IEnvironmentRepository>((ref) {
  return EnvironmentRepository(ref.watch(databaseProvider).environmentsDao);
});

final triggerRepositoryProvider = Provider<ITriggerRepository>((ref) {
  return TriggerRepository(ref.watch(databaseProvider).triggersDao);
});

final contextCardRepositoryProvider = Provider<IContextCardRepository>((ref) {
  return ContextCardRepository(ref.watch(databaseProvider).contextCardsDao);
});

final bleEncounterRepositoryProvider = Provider<IBleEncounterRepository>((ref) {
  return BleEncounterRepository(ref.watch(databaseProvider).bleEncountersDao);
});
