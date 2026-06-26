// Entry Point do App Sopro.
// Inicializa o Flutter, envolve o app com ProviderScope (Riverpod)
// e define as rotas de navegação.
// O banco de dados é criado de forma lazy pelo databaseProvider no primeiro acesso.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/strings.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO Sprint 5: await NotificationService.initialize();
  // TODO Sprint 6: await BLEService.initialize();

  runApp(const ProviderScope(child: SoproApp()));
}

// Widget raiz do Sopro.
// ProviderScope é obrigatório para o Riverpod funcionar.
class SoproApp extends ConsumerWidget {
  const SoproApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppStrings.appName,
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
