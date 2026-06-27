// Entry Point do App Sopro.
// O ProviderScope envolve todo o app — obrigatório para o Riverpod.
// O AppInitializer inicializa serviços assíncronos (notificações, GPS)
// dentro do escopo dos providers, sem necessidade de ProviderContainer manual.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/strings.dart';
import 'core/theme/app_theme.dart';
import 'infrastructure/background/background_service_manager.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/widgets/app_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura o foreground service antes de iniciar o app.
  // configure() deve ser chamado antes de runApp() — registra o entry point
  // do isolate de background para que o OS possa iniciá-lo corretamente.
  await BackgroundServiceManager.configure();

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
      home: const HomeScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}
