import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Serviço responsável por mostrar notificações locais ao usuário.
// Usado pelo FireTriggersUseCase para exibir o "sussurro" quando o
// usuário entra em um geofence com triggers ativos.
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
  static const backgroundChannelId   = 'sopro_background';
  static const _backgroundChannelName = 'Sopro ativo';
  static const _backgroundChannelDesc = 'Monitoramento de ambientes em segundo plano';

  // Inicializa o plugin e cria ambos os canais de notificação no Android.
  // Deve ser chamado uma vez, no AppInitializer, antes do runApp.
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

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

  // Solicita permissão de notificação em Android 13+ (API 33).
  // Em versões anteriores, retorna true automaticamente.
  Future<bool> requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return granted ?? true;
  }

  // Exibe uma notificação de trigger (o "sussurro").
  // [id] deve ser único para não sobrescrever outra notificação pendente.
  Future<void> showTrigger({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = AndroidNotificationDetails(
      _triggerChannelId,
      _triggerChannelName,
      channelDescription: _triggerChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(id, title, body, const NotificationDetails(android: details));
  }
}
