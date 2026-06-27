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
    _init();
  }

  Future<void> _init() async {
    // 1. Inicializa o canal de notificações no Android
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();
    await notifications.requestPermission();

    // 2. Solicita permissão de GPS e inicia monitoramento de geofences
    await ref.read(geofenceManagerProvider).start();

    // 3. Inicia o foreground service APÓS o primeiro frame ser renderizado.
    // addPostFrameCallback garante que a UI já está visível antes de iniciar
    // o serviço, evitando tela preta caso start() bloqueie ou lance exceção.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundService();
    });
  }

  // Separado de _init para isolar falhas do serviço: o app nunca pode mostrar
  // tela preta por causa do background service.
  Future<void> _startBackgroundService() async {
    try {
      await BackgroundServiceManager.start();
    } catch (e) {
      // Falha no serviço é não-fatal: GPS em foreground continua funcionando
      debugPrint('[AppInitializer] Background service não iniciado: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
