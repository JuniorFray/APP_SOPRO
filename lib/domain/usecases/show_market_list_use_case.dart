import '../repositories/i_shopping_list_repository.dart';
import '../../infrastructure/logging/core/logger.dart';
import '../../infrastructure/notifications/notification_service.dart';

// Caso de uso: ao entrar num ambiente tipo MERCADO (isMarket == true), busca os
// itens de compra PENDENTES (não marcados) e dispara UMA notificação com a lista
// (InboxStyle). Espelha o FireTriggersUseCase (mesmo padrão de cooldown/debounce),
// mas trocando triggers por itens da lista de compras.
//
// Callbacks avaliados no momento da execução para respeitar as preferências do
// usuário sem recriar o use case (toggle geral, som, cooldown).
class ShowMarketListUseCase {
  final IShoppingListRepository _shoppingRepo;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;
  final bool Function() _soundEnabled;
  final int Function() _cooldownMinutes;

  // Cooldown geral entre notificações (mesma preferência dos gatilhos)
  DateTime? _lastNotifTime;

  // Debounce por ambiente: evita disparo duplicado dentro de 60s quando
  // GeofenceManager (GPS) e GeofenceReceiver (nativo) detectam o mesmo ENTER.
  final _envLastFired = <String, DateTime>{};
  static const _debounceSecs = 60;

  ShowMarketListUseCase(
    this._shoppingRepo,
    this._notifications,
    this._notificationsEnabled,
    this._soundEnabled,
    this._cooldownMinutes,
  );

  // Dispara a notificação de lista de compras do mercado [environmentId].
  Future<void> call(String environmentId, String environmentName) async {
    if (!_notificationsEnabled()) return;

    // Cooldown geral
    final cooldown = _cooldownMinutes();
    if (cooldown > 0 && _lastNotifTime != null) {
      final elapsed = DateTime.now().difference(_lastNotifTime!);
      if (elapsed.inMinutes < cooldown) return;
    }

    // Debounce por ambiente (ENTER duplicado GPS + nativo)
    final lastFired = _envLastFired[environmentId];
    if (lastFired != null &&
        DateTime.now().difference(lastFired).inSeconds < _debounceSecs) {
      Logger.debug('duplicate_market_blocked', payload: {
        'environment_id': environmentId,
      }, feature: 'notification', action: 'debounce');
      return;
    }

    final pending = await _shoppingRepo.getPendingByEnvironment(environmentId);
    if (pending.isEmpty) return; // nada pendente → não notifica nem marca timer

    _lastNotifTime = DateTime.now();
    _envLastFired[environmentId] = DateTime.now();
    final withSound = _soundEnabled();
    final names = pending.map((i) => i.name).toList();

    Logger.info('market_list_fired', payload: {
      'environment_id':   environmentId,
      'environment_name': environmentName,
      'pending_count':    names.length,
      'with_sound':       withSound,
    }, feature: 'notification', action: 'fire');

    try {
      await _notifications.showMarketList(
        // ID único por ambiente (mesmo esquema dos triggers: hash positivo)
        id: environmentId.hashCode & 0x7FFFFFFF,
        environmentName: environmentName,
        pendingItemNames: names,
        payload: environmentId,
        useSoundChannel: withSound,
      );

      Logger.info('notification_displayed', payload: {
        'environment_id': environmentId,
        'kind':           'market_list',
        'with_sound':     withSound,
      }, feature: 'notification', action: 'display');
    } catch (e, st) {
      Logger.error('notification_error', payload: {
        'environment_id': environmentId,
        'kind':           'market_list',
      }, exception: e, stackTrace: st, feature: 'notification', action: 'display_failed');
    }
  }
}
