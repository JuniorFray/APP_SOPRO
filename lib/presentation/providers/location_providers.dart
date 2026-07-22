import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/fire_triggers_use_case.dart';
import '../../domain/usecases/show_market_list_use_case.dart';
import '../../infrastructure/geofence/geofence_manager.dart';
import '../../infrastructure/geofence/native_geofence_service.dart';
import '../../infrastructure/location/native_location_service.dart';
import '../../infrastructure/notifications/notification_service.dart';
import 'database_provider.dart';
import 'settings_providers.dart';

// Provider do NotificationService — singleton criado uma vez por sessão.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// Provider do NativeLocationService — wrapper dos canais nativos de GPS.
// Singleton: uma instância por sessão, sem estado entre chamadas.
final nativeLocationServiceProvider = Provider<NativeLocationService>((ref) {
  return NativeLocationService();
});

// Provider do NativeGeofenceService — wrapper do GeofencingClient Android.
// Singleton: o PendingIntent interno é reutilizado em todas as chamadas.
final nativeGeofenceServiceProvider = Provider<NativeGeofenceService>((ref) {
  return NativeGeofenceService();
});

// Provider do GeofenceManager — injeta repositórios, use cases e serviços nativos.
// O manager é criado mas não iniciado aqui; HomeScreen chama .start().
final geofenceManagerProvider = Provider<GeofenceManager>((ref) {
  final envRepo         = ref.watch(environmentRepositoryProvider);
  final triggerRepo     = ref.watch(triggerRepositoryProvider);
  final shoppingRepo    = ref.watch(shoppingListRepositoryProvider);
  final activityLog     = ref.watch(activityLogRepositoryProvider);
  final notifications   = ref.watch(notificationServiceProvider);
  final locationService = ref.watch(nativeLocationServiceProvider);
  final nativeGeofence  = ref.watch(nativeGeofenceServiceProvider);

  // FireTriggersUseCase recebe callbacks que leem as preferências do usuário
  // no momento em que um geofence é acionado — assim qualquer alteração nas
  // Configurações é imediatamente respeitada sem recriar o GeofenceManager.
  final fireTriggers = FireTriggersUseCase(
    triggerRepo,
    notifications,
    activityLog,
    () => ref.read(notificationsEnabledProvider),        // toggle geral
    () => ref.read(notificationSoundProvider),            // som vs. silencioso
    () => ref.read(notificationCooldownMinutesProvider),  // cooldown
  );

  // Mesmas preferências, mas para ambientes tipo Mercado (lista de compras).
  final showMarketList = ShowMarketListUseCase(
    shoppingRepo,
    notifications,
    () => ref.read(notificationsEnabledProvider),
    () => ref.read(notificationSoundProvider),
    () => ref.read(notificationCooldownMinutesProvider),
  );

  final manager = GeofenceManager(
    envRepo,
    fireTriggers,
    showMarketList,
    locationService,
    nativeGeofence,
    activityLog,
  );

  // Garante que o stream de GPS seja cancelado quando o provider for descartado
  ref.onDispose(manager.stop);

  return manager;
});
