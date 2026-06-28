import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Serviço responsável por mostrar notificações locais e tratar toques nelas.
//
// Canais Android criados em initialize():
//   'sopro_triggers'        — alta prioridade, com som (entrada em geofence)
//   'sopro_triggers_silent' — prioridade padrão, sem som (preferência do usuário)
//   'sopro_background'      — baixa prioridade, notificação persistente do foreground
//
// Deep-link:
//   Ao tocar numa notificação de trigger, o payload (environmentId) é entregue
//   ao callback registrado via setOnTapCallback(). O AppInitializer registra
//   esse callback apontando para o navigatorKey global.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // Canal com som — alta prioridade, exibido em heads-up ao entrar no geofence
  static const _triggerChannelId   = 'sopro_triggers';
  static const _triggerChannelName = 'Gatilhos Sopro';
  static const _triggerChannelDesc = 'Sussurros entregues ao chegar em um local';

  // Canal silencioso — sem som/vibração, para usuários que preferem discreção
  static const _silentChannelId   = 'sopro_triggers_silent';
  static const _silentChannelName = 'Gatilhos Sopro (silencioso)';
  static const _silentChannelDesc = 'Sussurros sem som nem vibração';

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

    // Canal com som — alta prioridade para os triggers de geofence
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _triggerChannelId,
        _triggerChannelName,
        description: _triggerChannelDesc,
        importance: Importance.high,
      ),
    );

    // Canal silencioso — prioridade padrão, sem som nem vibração
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _silentChannelId,
        _silentChannelName,
        description: _silentChannelDesc,
        importance: Importance.defaultImportance,
        enableVibration: false,
        playSound: false,
        showBadge: true,
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
  Future<String?> checkLaunchFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  // Solicita permissão de notificação em Android 13+ (API 33).
  Future<bool> requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return granted ?? true;
  }

  // Exibe uma notificação de trigger — o "sussurro" do Sopro.
  //
  // [id]             — deve ser único por trigger (usa hash do UUID)
  // [title]          — "nome do trigger • nome do ambiente"
  // [body]           — conteúdo detalhado do trigger
  // [payload]        — environmentId para deep-link ao tocar
  // [useSoundChannel] — true = canal com som; false = canal silencioso
  Future<void> showTrigger({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool useSoundChannel = true,
  }) async {
    // Seleciona canal conforme preferência de som do usuário
    final channelId   = useSoundChannel ? _triggerChannelId   : _silentChannelId;
    final channelName = useSoundChannel ? _triggerChannelName : _silentChannelName;
    final channelDesc = useSoundChannel ? _triggerChannelDesc : _silentChannelDesc;
    final importance  = useSoundChannel ? Importance.high : Importance.defaultImportance;
    final priority    = useSoundChannel ? Priority.high   : Priority.defaultPriority;

    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }
}
