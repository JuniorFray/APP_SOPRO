import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/navigation/app_router.dart';
import '../../infrastructure/background/background_service_manager.dart';
import '../../infrastructure/notifications/notification_service.dart';
import '../providers/location_providers.dart';
import '../providers/settings_providers.dart';

// Widget que inicializa serviços assíncronos dentro do ProviderScope.
// Deve ser o primeiro widget construído depois do ProviderScope para que o
// NotificationService seja configurado antes da primeira tela ser exibida.
//
// Sequência de _init():
//   1. Registra o callback de toque em notificação (antes de initialize(),
//      para não perder toques em notificações já pendentes).
//   2. Inicializa o plugin de notificações e cria os canais Android.
//   3. Verifica cold start (app aberto por toque numa notificação).
//   4. Inicia o foreground service se o onboarding já foi concluído.
//
// INTENCIONALMENTE não solicita permissões aqui:
//   Permissões são solicitadas no Onboarding com contexto explicativo.
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
    // 1. Registra o callback de toque ANTES de initialize() para que notificações
    //    pendentes (ex: do último foreground service) sejam capturadas.
    NotificationService.setOnTapCallback(_openEnvironment);

    // 2. Cria os dois canais Android e registra os handlers do plugin.
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();

    // 3. Verifica cold start: app aberto pelo toque numa notificação.
    //    Só acontece quando o processo foi encerrado (force-stop ou reboot).
    //    Com o foreground service ativo, o processo raramente é encerrado.
    final coldPayload = await notifications.checkLaunchFromNotification();
    if (coldPayload != null) {
      // Aguarda o primeiro frame para que o Navigator esteja montado
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEnvironment(coldPayload);
      });
    }

    final prefs = await SharedPreferences.getInstance();

    // 4. Restaura a preferência de notificações salva pelo usuário nas Configurações.
    //    O default (true) já está no provider; só atualiza se o usuário desativou.
    final notifEnabled = prefs.getBool('notifications_enabled') ?? true;
    if (!notifEnabled) {
      ref.read(notificationsEnabledProvider.notifier).state = false;
    }

    // 5. Inicia o foreground service apenas se o onboarding já foi concluído.
    //    Evita exibir "Sopro ativo" antes de o usuário configurar o app.
    if (prefs.getBool('onboarding_done') ?? false) {
      await BackgroundServiceManager.start();
    }
  }

  // Navega para a tela do ambiente identificado por [environmentId].
  // Chamado tanto pelo toque em notificação (app em segundo plano)
  // quanto pelo cold start (app fechado).
  //
  // Usa o navigatorKey global para navegar de fora da árvore de widgets.
  void _openEnvironment(String environmentId) {
    navigatorKey.currentState?.pushNamed(
      '/environment',
      arguments: environmentId,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
