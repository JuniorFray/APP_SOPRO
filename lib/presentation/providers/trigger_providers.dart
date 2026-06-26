import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/trigger_entity.dart';
import 'database_provider.dart';

// Observa os triggers de um ambiente em tempo real.
// Recebe o environmentId como parâmetro de família.
final triggersByEnvironmentProvider =
    StreamProvider.family<List<TriggerEntity>, String>((ref, environmentId) {
  return ref
      .watch(triggerRepositoryProvider)
      .watchByEnvironment(environmentId);
});
