import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/fire_triggers_use_case.dart';
import '../../infrastructure/geofence/geofence_manager.dart';
import '../../infrastructure/location/native_location_service.dart';
import '../../infrastructure/notifications/notification_service.dart';
import 'database_provider.dart';

// Provider do NotificationService — singleton criado uma vez por sessão.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// Provider do NativeLocationService — wrapper dos canais nativos de GPS.
// Singleton: uma instância por sessão, sem estado entre chamadas.
final nativeLocationServiceProvider = Provider<NativeLocationService>((ref) {
  return NativeLocationService();
});

// Provider do GeofenceManager — injeta repositórios, use case e serviço de GPS.
// O manager é criado mas não iniciado aqui; AppInitializer chama .start().
final geofenceManagerProvider = Provider<GeofenceManager>((ref) {
  final envRepo = ref.watch(environmentRepositoryProvider);
  final triggerRepo = ref.watch(triggerRepositoryProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final locationService = ref.watch(nativeLocationServiceProvider);

  // FireTriggersUseCase não tem estado próprio — criado aqui sem provider dedicado
  final fireTriggers = FireTriggersUseCase(triggerRepo, notifications);

  final manager = GeofenceManager(envRepo, fireTriggers, locationService);

  // Garante que o stream de GPS seja cancelado quando o provider for descartado
  ref.onDispose(manager.stop);

  return manager;
});
