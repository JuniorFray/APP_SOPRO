// main.dart - Entry Point do App Sopro
//
// Inicializa o Flutter, envolve o app com ProviderScope (Riverpod)
// e define as rotas de navegacao.
// Servicos de sistema (GPS, BLE, Notificacoes) serao inicializados
// aqui conforme cada Sprint for implementado.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';

Future<void> main() async {
  // Garante bindings do Flutter antes de chamadas assincronas
  WidgetsFlutterBinding.ensureInitialized();

  // TODO Sprint 1: await DatabaseService.initialize();
  // TODO Sprint 2: await LocationService.initialize();
  // TODO Sprint 5: await NotificationService.initialize();
  // TODO Sprint 6: await BLEService.initialize();

  runApp(const ProviderScope(child: SoproApp()));
}

/// Widget raiz do Sopro.
/// ProviderScope e obrigatorio para o Riverpod funcionar.
class SoproApp extends ConsumerWidget {
  const SoproApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Sopro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}