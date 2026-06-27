import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Serviço responsável por mostrar notificações locais e tratar toques nelas.
//
// Dois canais Android:
//   'sopro_triggers'  — alta prioridade, exibido quando entra em geofence
//   'sopro_background' — baixa prioridade, notificação persistente do foreground service
//
// Deep-link:
//   Ao tocar numa notificação de trigger, o payload (environmentId) é entregue
//   ao callback registrado via setOnTapCallback(). O AppInitializer registra
//   esse callback apontando para o navigatorKey global.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // Canal de triggers — alta prioridade, exibido quando entra em um geofence
  static const _triggerChannelId   = 'sopro_triggers';
  static const _triggerChannelName = 'Gatilhos Sopro';
  static const _triggerChannelDesc = 'Sussurros entregues ao chegar em um local';

  // Canal do foreground service — baixa prioridade (sem som, sem heads-up).
  // Deve ser criado ANTES de BackgroundServiceManager.start() para evitar o
  // erro "Bad notification for startForeground" no Android 8+.
  // O ID é público para que BackgroundServiceManager possa referenciá-lo.
  static const backgroundChannelId    = 'sopro_background';
  static const _backgroundChannelName = 'Sopro ativo';
  static const _backgroundChannelDesc = 'Monitoramento de ambientes em segundo plano';

  // Callback chamado quando o usuário toca numa notificação de trigger.
  // Recebe o payload (environmentId) e deve navegar para a tela do ambiente.
  // Registrado pelo AppInitializer via setOnTapCallback().
  static void Function(String environmentId)? _onTap;

  // Registra o callback de navegação — deve ser chamado antes de initialize().
  static void setOnTapCallback(void Function(String environmentId) callback) {
    _onTap = callback;
  }

  // Inicializa o plugin, registra o handler de toque e cria os canais Android.
  // Deve ser chamado uma vez no AppInitializer, antes de BackgroundServiceManager.start().
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      // Chamado quando o usuário toca na notificação enquanto o app está
      // em primeiro plano OU em segundo plano (processo vivo pelo foreground service).
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onTap?.call(payload);
        }
      },
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Canal de alta prioridade para os triggers de geofence
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _triggerChannelId,
        _triggerChannelName,
        description: _triggerChannelDesc,
        importance: Importance.high,
      ),
    );

    // Canal de baixa prioridade para a notificação persistente do foreground service.
    // Criado aqui para que exista antes de BackgroundServiceManager.start().
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        backgroundChannelId,
        _backgroundChannelName,
        description: _backgroundChannelDesc,
        importance: Importance.low, // sem som, sem popup
        showBadge: false,
      ),
    );
  }

  // Verifica se o app foi aberto pelo toque numa notificação (cold start).
  // Retorna o environmentId do payload, ou null se o app foi aberto normalmente.
  //
  // Cold start acontece quando o processo foi completamente encerrado (force-stop
  // ou reinício do dispositivo) e o usuário toca na notificação.
  // Com o foreground service ativo, o processo raramente é encerrado —
  // mas esta verificação cobre o caso de exceção.
  Future<String?> checkLaunchFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  // Solicita permissão de notificação em Android 13+ (API 33).
  // Em versões anteriores, retorna true automaticamente.
  Future<bool> requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return granted ?? true;
  }

  // Exibe uma notificação de trigger — o "sussurro" do Sopro.
  //
  // [id]      — deve ser único por trigger (usa hash do UUID) para não
  //             sobrescrever outra notificação pendente do mesmo ambiente.
  // [title]   — título curto: "nome do trigger • nome do ambiente"
  // [body]    — conteúdo detalhado do trigger
  // [payload] — ID do ambiente; passado de volta ao callback de toque
  //             para navegar diretamente para a tela do ambiente.
  Future<void> showTrigger({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = AndroidNotificationDetails(
      _triggerChannelId,
      _triggerChannelName,
      channelDescription: _triggerChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: details),
      payload: payload,
    );
  }
}
