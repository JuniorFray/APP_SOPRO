import '../repositories/i_trigger_repository.dart';
import '../../infrastructure/notifications/notification_service.dart';

// Caso de uso: dado um Environment ao qual o usuário acabou de entrar,
// busca todos os triggers ATIVOS daquele ambiente e dispara uma
// notificação para cada um — o "sussurro" do Sopro.
//
// [_notificationsEnabled] é um callback avaliado no momento da execução,
// permitindo que o toggle de notificações nas Configurações desative os
// sussurros sem recriar o use case.
class FireTriggersUseCase {
  final ITriggerRepository _triggerRepo;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;

  FireTriggersUseCase(
    this._triggerRepo,
    this._notifications,
    this._notificationsEnabled,
  );

  // Dispara as notificações dos triggers ativos do ambiente [environmentId].
  // [environmentName] é exibido no título da notificação como contexto.
  // Retorna silenciosamente sem fazer nada se notificações estiverem desativadas.
  Future<void> call(String environmentId, String environmentName) async {
    // Respeita o toggle de notificações configurado pelo usuário
    if (!_notificationsEnabled()) return;

    final triggers = await _triggerRepo.getActiveByEnvironment(environmentId);

    for (var i = 0; i < triggers.length; i++) {
      final trigger = triggers[i];
      await _notifications.showTrigger(
        // ID da notificação: hash positivo do UUID — colisões são improváveis
        // para a quantidade de triggers que um usuário típico terá
        id: trigger.id.hashCode & 0x7FFFFFFF,
        // Título mostra o nome do ambiente para contextualizar o sussurro
        title: '${trigger.title} • $environmentName',
        body: trigger.content,
        // Payload = ID do ambiente: ao tocar na notificação, o app navega
        // diretamente para a EnvironmentDetailScreen deste ambiente
        payload: environmentId,
      );
    }
  }
}
