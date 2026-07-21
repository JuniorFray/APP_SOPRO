import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Serviço responsável por mostrar notificações locais e tratar toques nelas.
//
// Canais Android criados em initialize():
//   'sopro_triggers'        — prioridade MÁXIMA, com som (entrada em geofence)
//   'sopro_triggers_silent' — prioridade padrão, sem som (preferência do usuário)
//   'sopro_background'      — baixa prioridade, notificação persistente do foreground
//
// Importance.max (IMPORTANCE_MAX = 5) no canal garante heads-up em OEMs como
// Motorola My UX e Samsung One UI, que ignoram Importance.high em segundo plano.
//
// Deep-link:
//   Ao tocar numa notificação de trigger, o payload (environmentId) é entregue
//   ao callback registrado via setOnTapCallback(). O AppInitializer registra
//   esse callback apontando para o navigatorKey global.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // Canal com som — prioridade MÁXIMA para garantir heads-up em qualquer OEM
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
    // 'notification_icon' refere-se a res/drawable/notification_icon.xml —
    // drawable monocromático (branco + transparente) exigido pelo Android 5.0+.
    // Usar '@mipmap/ic_launcher' como smallIcon causa o quadrado branco na barra.
    const androidSettings =
        AndroidInitializationSettings('notification_icon');
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

    // Canal com som — IMPORTANCE_MAX (5) para garantir heads-up mesmo em OEMs
    // restritivos (Motorola My UX, Samsung One UI).
    // ATENÇÃO: se o canal já existe com importance menor (instalações anteriores),
    // o Android mantém a configuração do usuário — reinstalar o app ou limpar
    // dados de notificação reseta o canal para este valor.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _triggerChannelId,
        _triggerChannelName,
        description: _triggerChannelDesc,
        importance: Importance.max,
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
    // Priority.max + Importance.max = combinação necessária para heads-up garantido.
    // Importance.max no canal define o teto; priority na notificação define a entrega.
    final importance = useSoundChannel ? Importance.max            : Importance.defaultImportance;
    final priority   = useSoundChannel ? Priority.max              : Priority.defaultPriority;

    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      // drawable monocromático — mesmo recurso do AndroidInitializationSettings
      icon: 'notification_icon',
      // ticker: texto exibido na barra de status no momento da chegada —
      // necessário para acionar o heads-up em alguns OEMs (Motorola, Samsung).
      ticker: title,
      // public: exibe conteúdo completo na tela de bloqueio (sem mascarar).
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  // Exibe a notificação de LISTA DE COMPRAS ao entrar num mercado (isMarket).
  // Usa InboxStyle para listar os itens pendentes como linhas, no mesmo canal e
  // importância de showTrigger().
  //
  // TODO upgrade: quando o checkbox interativo nativo for implementado, cada
  // linha desta notificação passa a ter uma ação de toque individual que chama
  // ShoppingListRepository.toggleChecked() sem abrir o app.
  Future<void> showMarketList({
    required int id,
    required String environmentName,
    required List<String> pendingItemNames,
    String? payload,
    bool useSoundChannel = true,
  }) async {
    final channelId   = useSoundChannel ? _triggerChannelId   : _silentChannelId;
    final channelName = useSoundChannel ? _triggerChannelName : _silentChannelName;
    final channelDesc = useSoundChannel ? _triggerChannelDesc : _silentChannelDesc;
    final importance = useSoundChannel ? Importance.max : Importance.defaultImportance;
    final priority   = useSoundChannel ? Priority.max   : Priority.defaultPriority;

    final title = 'Lista de compras — $environmentName';
    // Corpo colapsado: resumo dos itens em uma linha.
    final body = pendingItemNames.join(', ');

    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      icon: 'notification_icon',
      ticker: title,
      visibility: NotificationVisibility.public,
      // InboxStyle: cada item pendente vira uma linha da notificação expandida.
      styleInformation: InboxStyleInformation(
        pendingItemNames,
        contentTitle: title,
        summaryText: '${pendingItemNames.length} itens',
      ),
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
