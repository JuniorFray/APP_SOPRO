import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/background/background_service_manager.dart';
import '../providers/location_providers.dart';

// Widget que inicializa serviços assíncronos dentro do ProviderScope.
// Deve ser o primeiro widget construído depois do ProviderScope para que o
// NotificationService seja configurado antes da primeira tela ser exibida.
//
// INTENCIONALMENTE não solicita permissões aqui:
//   - Permissões (localização, notificações, BLE) são solicitadas no Onboarding,
//     mostrando o valor antes de pedir cada permissão.
//   - Geofences são iniciados pelo HomeScreen após confirmar que o perfil existe.
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
    // 1. Cria os dois canais Android (triggers + background service).
    //    O canal 'sopro_background' deve existir antes de startService().
    await ref.read(notificationServiceProvider).initialize();

    // 2. Inicia o foreground service apenas se o onboarding já foi concluído.
    //    Evita exibir "Sopro ativo" antes de o usuário configurar o app.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_done') ?? false) {
      await BackgroundServiceManager.start();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
