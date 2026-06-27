import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Inicializa o plugin de notificações e cria o canal Android.
    // NÃO pede permissão aqui — o Onboarding explica e pede na ordem certa.
    await ref.read(notificationServiceProvider).initialize();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
