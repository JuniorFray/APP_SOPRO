import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/fire_triggers_use_case.dart';
import '../../infrastructure/geofence/geofence_manager.dart';
import '../../infrastructure/notifications/notification_service.dart';
import 'database_provider.dart';

// Provider do NotificationService — singleton criado uma vez por sessão.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// Provider do GeofenceManager — injeta os repositórios e o use case.
// O manager é criado mas não iniciado aqui; o AppInitializer chama .start().
final geofenceManagerProvider = Provider<GeofenceManager>((ref) {
  final envRepo = ref.watch(environmentRepositoryProvider);
  final triggerRepo = ref.watch(triggerRepositoryProvider);
  final notifications = ref.watch(notificationServiceProvider);

  // Use case criado aqui (não precisa de provider próprio — sem estado)
  final fireTriggers = FireTriggersUseCase(triggerRepo, notifications);

  final manager = GeofenceManager(envRepo, fireTriggers);

  // Garante que o serviço seja parado quando o provider for descartado
  ref.onDispose(manager.stop);

  return manager;
});
