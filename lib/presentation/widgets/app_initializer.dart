import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    _init();
  }

  Future<void> _init() async {
    // 1. Inicializa o canal de notificações no Android
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();
    await notifications.requestPermission();

    // 2. Solicita permissão de GPS e inicia monitoramento de geofences
    await ref.read(geofenceManagerProvider).start();

    // TODO Sprint 7: iniciar BackgroundServiceManager.start() aqui.
    // Desativado até sprint dedicado (requer canal de notificação pré-criado).
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
