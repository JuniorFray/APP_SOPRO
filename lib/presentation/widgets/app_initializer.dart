import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/background/background_service_manager.dart';
import '../providers/location_providers.dart';

// Widget que inicializa serviços assíncronos dentro do ProviderScope.
// Deve ser o primeiro widget construído depois do ProviderScope para
// garantir que NotificationService, GeofenceManager e BackgroundService
// sejam preparados antes da primeira tela ser exibida ao usuário.
class AppInitializer extends ConsumerStatefulWidget {
  final Widget child;

  const AppInitializer({super.key, required this.child});

  @override
  ConsumerState<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<AppInitializer> {
  @override
  void initState() {
    super.initState();
    // initState não pode ser async — delega para método auxiliar
    _init();
  }

  Future<void> _init() async {
    // 1. Inicializa o canal de notificações no Android
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();
    await notifications.requestPermission();

    // 2. Solicita permissão de GPS e inicia monitoramento de geofences
    // As permissões de localização são solicitadas dentro do geofenceManager.start()
    await ref.read(geofenceManagerProvider).start();

    // 3. Inicia o foreground service para manter o processo vivo em background.
    // O serviço exibe uma notificação persistente que impede o Android de
    // matar o processo, permitindo que o GPS continue mesmo com o app minimizado.
    await BackgroundServiceManager.start();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
