// Entry Point do App Sopro.
// O ProviderScope envolve todo o app — obrigatório para o Riverpod.
// O AppInitializer inicializa serviços assíncronos dentro do escopo dos providers.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/strings.dart';
import 'core/constants/voice_content.dart';
import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'infrastructure/background/background_service_manager.dart';
import 'infrastructure/background/voice_action_worker.dart';
import 'presentation/screens/environment/environment_loader_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/shell/main_shell_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/widgets/app_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa dados de formatação de data para o pt_BR
  await initializeDateFormatting('pt_BR', null);

  // Registra o dispatcher Dart do WorkManager — chamado pelo FloatingVoiceService
  // para persistir ambientes e gatilhos via Drift sem abrir o app.
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

  // Carrega variáveis de ambiente do arquivo .env (incluído como Flutter asset).
  // mergeWith: {} evita exceção se .env não existir (instalação sem dotenv local).
  // A chave Gemini é lida em AppConstants.geminiApiKey via dotenv.env[].
  await dotenv.load(fileName: '.env', mergeWith: {});

  // Carrega a fonte unica de texto de voz (prompt + persona) antes do runApp,
  // para que AppConstants.geminiAssistantPrompt e AssistantPersona ja tenham o
  // asset em cache no primeiro uso de voz. Mesmo arquivo lido pelo overlay nativo.
  await VoiceContent.load();

  // Registra o entry-point do foreground service ANTES do runApp().
  // O canal de notificação é criado no AppInitializer._init() (após initialize()),
  // garantindo que exista antes de BackgroundServiceManager.start().
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

      // navigatorKey global permite navegar de fora da árvore de widgets.
      // Usado pelo NotificationService ao tratar toques em notificações de trigger.
      navigatorKey: navigatorKey,

      // MainShellScreen: bottom nav de 4 abas. Verifica o onboarding e
      // redireciona se necessário (herdado do antigo HomeScreen).
      home: const MainShellScreen(),
      routes: {
        '/home':       (_) => const MainShellScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/profile':    (_) => const ProfileScreen(),
        '/settings':   (_) => const SettingsScreen(),

        // Rota de deep-link para notificações de trigger.
        // O argumento é o ID do ambiente (String); a tela carrega a entidade
        // pelo ID e exibe EnvironmentDetailScreen ao receber o dado.
        '/environment': (ctx) {
          final id = ModalRoute.of(ctx)?.settings.arguments as String?;
          if (id == null) return const HomeScreen();
          return EnvironmentLoaderScreen(environmentId: id);
        },
      },
    );
  }
}
