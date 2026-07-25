// INotificationProvider — contrato comum de notificações (Tool Provider, spec
// voice_structure_doc/architecture/08-Tool-Providers.md).
//
// Abstrai a entrega de notificações locais (sussurros e lista de compras) para
// desacoplar as Skills do plugin concreto. Camada fina: NotificationService já
// implementa estes métodos — só declara `implements`, sem mudar canais/ícones.
//
// Membros estáticos (setOnTapCallback, backgroundChannelId) permanecem na
// classe concreta; o contrato cobre apenas a superfície de instância.
abstract class INotificationProvider {
  // Inicializa o plugin e cria os canais Android.
  Future<void> initialize();

  // Payload da notificação que abriu o app em cold start (ou null).
  Future<String?> checkLaunchFromNotification();

  // Solicita permissão de notificação (Android 13+).
  Future<bool> requestPermission();

  // Exibe a notificação de trigger — o "sussurro" do Sopro.
  Future<void> showTrigger({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool useSoundChannel = true,
  });

  // Exibe a notificação de lista de compras (InboxStyle) ao entrar num mercado.
  Future<void> showMarketList({
    required int id,
    required String environmentName,
    required List<String> pendingItemNames,
    String? payload,
    bool useSoundChannel = true,
  });
}
