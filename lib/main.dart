// Entry Point do App Sopro.
// O ProviderScope envolve todo o app — obrigatório para o Riverpod.
// O AppInitializer inicializa serviços assíncronos dentro do escopo dos providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/strings.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/widgets/app_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO Sprint 9: await BackgroundServiceManager.configure();
  // Desativado até sprint dedicado (requer canal de notificação pré-criado).

  runApp(
    const ProviderScope(
      child: AppInitializer(
        child: SoproApp(),
      ),
    ),
  );
}

// Widget raiz do Sopro.
class SoproApp extends ConsumerWidget {
  const SoproApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // HomeScreen verifica o onboarding e redireciona se necessário
      home: const HomeScreen(),
      routes: {
        '/home':       (_) => const HomeScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/profile':    (_) => const ProfileScreen(),
      },
    );
  }
}
