import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Serviço responsável por mostrar notificações locais ao usuário.
// Usado pelo FireTriggersUseCase para exibir o "sussurro" quando o
// usuário entra em um geofence com triggers ativos.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // ID do canal de triggers — precisa ser único por app no Android 8+
  static const _triggerChannelId = 'sopro_triggers';
  static const _triggerChannelName = 'Gatilhos Sopro';
  static const _triggerChannelDesc =
      'Sussurros entregues ao chegar em um local';

  // Inicializa o plugin e cria o canal de notificações no Android.
  // Deve ser chamado uma vez antes do runApp.
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    // Cria o canal de alta prioridade para os triggers — exige Android 8+
    const channel = AndroidNotificationChannel(
      _triggerChannelId,
      _triggerChannelName,
      description: _triggerChannelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
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
