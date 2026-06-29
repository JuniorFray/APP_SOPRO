import '../repositories/i_trigger_repository.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../infrastructure/notifications/notification_service.dart';

// Caso de uso: dado um Environment ao qual o usuário acabou de entrar,
// busca todos os triggers ATIVOS daquele ambiente e dispara uma
// notificação para cada um — o "sussurro" do Sopro.
//
// Callbacks avaliados no momento da execução (não no momento de criação)
// para que as configurações do usuário sejam respeitadas sem recriar o use case:
//   [_notificationsEnabled] — toggle geral de notificações
//   [_soundEnabled]         — usar canal com som vs. canal silencioso
//   [_cooldownMinutes]      — intervalo mínimo entre notificações (0 = sem limite)
class FireTriggersUseCase {
  final ITriggerRepository _triggerRepo;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;
  final bool Function() _soundEnabled;
  final int Function() _cooldownMinutes;

  // Rastreia o último disparo para aplicar o cooldown configurado pelo usuário
  DateTime? _lastNotifTime;

  FireTriggersUseCase(
    this._triggerRepo,
    this._notifications,
    this._notificationsEnabled,
    this._soundEnabled,
    this._cooldownMinutes,
  );

  // Dispara as notificações dos triggers ativos do ambiente [environmentId].
  // [environmentName] é exibido no título da notificação como contexto.
  Future<void> call(String environmentId, String environmentName) async {
    // Respeita o toggle global de notificações
    if (!_notificationsEnabled()) return;

    // Aplica cooldown: ignora se a última notificação foi há menos de X minutos
    final cooldown = _cooldownMinutes();
    if (cooldown > 0 && _lastNotifTime != null) {
      final elapsed = DateTime.now().difference(_lastNotifTime!);
      if (elapsed.inMinutes < cooldown) return;
    }

    final triggers = await _triggerRepo.getActiveByEnvironment(environmentId);
    if (triggers.isEmpty) return; // sem triggers ativos, não atualiza o timer

    // Marca o tempo do disparo antes de enviar as notificações
    _lastNotifTime = DateTime.now();
    final withSound = _soundEnabled();

    for (final trigger in triggers) {
      // Loga a intenção de disparar — confirmação de que o use case chegou aqui.
      // Se trigger_fired aparece no Supabase mas notification_displayed não,
      // o problema está em showTrigger() → flutter_local_notifications → Android.
      AppLogger.log('trigger_fired', {
        'environment_id':   environmentId,
        'environment_name': environmentName,
        'trigger_id':       trigger.id,
        'trigger_title':    trigger.title,
        'with_sound':       withSound,
      });

      try {
        await _notifications.showTrigger(
          // ID da notificação: hash positivo do UUID
          id: trigger.id.hashCode & 0x7FFFFFFF,
          // Título mostra o ambiente para contextualizar o sussurro
          title: '${trigger.title} • $environmentName',
          body: trigger.content,
          // Payload = ID do ambiente para navegar diretamente ao tocar
          payload: environmentId,
          // Canal escolhido conforme preferência de som do usuário
          useSoundChannel: withSound,
        );

        // Loga apenas se show() completou sem exceção — indica que a API Android
        // recebeu a notificação. Se este evento não aparece no Supabase, o problema
        // está no flutter_local_notifications (plugin crash, permissão revogada, etc.).
        AppLogger.log('notification_displayed', {
          'trigger_id':     trigger.id,
          'trigger_title':  trigger.title,
          'environment_id': environmentId,
          'with_sound':     withSound,
        });
      } catch (e) {
        // Loga falha de exibição — ajuda a identificar exceções do plugin/canal
        AppLogger.log('notification_error', {
          'trigger_id': trigger.id,
          'error':      e.toString(),
        });
      }
    }
  }
}
