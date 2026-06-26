import '../repositories/i_trigger_repository.dart';
import '../../infrastructure/notifications/notification_service.dart';

// Caso de uso: dado um Environment ao qual o usuário acabou de entrar,
// busca todos os triggers ATIVOS daquele ambiente e dispara uma
// notificação para cada um — o "sussurro" do Sopro.
//
// Separado da infra de geofence para que o teste unitário possa verificar
// o comportamento sem depender de GPS ou notificações reais.
class FireTriggersUseCase {
  final ITriggerRepository _triggerRepo;
  final NotificationService _notifications;

  FireTriggersUseCase(this._triggerRepo, this._notifications);

  // Dispara as notificações dos triggers ativos do ambiente [environmentId].
  // [environmentName] é exibido no título da notificação como contexto.
  Future<void> call(String environmentId, String environmentName) async {
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
      );
    }
  }
}
