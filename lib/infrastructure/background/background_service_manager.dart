import 'package:flutter_background_service/flutter_background_service.dart';

// Gerencia o ciclo de vida do foreground service do Sopro.
//
// O foreground service exibe uma notificação persistente que impede o Android
// de matar o processo do app quando o usuário minimiza. Com o processo vivo,
// o motor Flutter principal (com o EventChannel de GPS) continua funcionando,
// e o GeofenceManager continua monitorando os ambientes cadastrados.
//
// Uso:
//   1. await BackgroundServiceManager.configure()  — antes de runApp()
//   2. await BackgroundServiceManager.start()      — no AppInitializer
class BackgroundServiceManager {
  // ID do canal de notificação criado pelo serviço no Android
  static const _channelId = 'sopro_background';

  // ID da notificação do foreground service — diferente do canal de triggers (sopro_triggers)
  static const _notifId = 888;

  // Configura o serviço: deve ser chamado UMA VEZ antes de runApp().
  static Future<void> configure() async {
    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundStart,
        autoStart: false,   // iniciado explicitamente pelo AppInitializer
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Sopro ativo',
        initialNotificationContent: 'Monitorando seus ambientes em segundo plano',
        foregroundServiceNotificationId: _notifId,
      ),
      // iOS: background fetch configurado separadamente fora do escopo do Sprint 6
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  // Inicia o foreground service — chamar no AppInitializer após as permissões.
  static Future<void> start() async {
    await FlutterBackgroundService().startService();
  }

  // Para o serviço (ex: botão "parar monitoramento" em configurações futuras).
  static void stop() {
    FlutterBackgroundService().invoke('stop');
  }
}

// Entry point do isolate de background — DEVE ser top-level e anotado.
// O Android chama este método quando o serviço é iniciado pelo OS.
// Apenas mantém o foreground service ativo: o GPS roda no motor principal.
//
// Nota: flutter_background_service 5.x registra os plugins internamente;
// não é necessário chamar DartPluginRegistrant manualmente.
@pragma('vm:entry-point')
void _onBackgroundStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    // Escuta o evento 'stop' enviado pelo motor principal via invoke()
    service.on('stop').listen((_) => service.stopSelf());

    // Promove o serviço para modo foreground (exibe a notificação persistente)
    service.setAsForegroundService();
  }
}
