import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/strings.dart';
import '../../domain/entities/context_card_entity.dart';
import '../logging/core/correlation_manager.dart';
import '../logging/core/logger.dart';
import 'discovered_sopro_user.dart';

// BleService gerencia toda a comunicação BLE do Sopro 100% via canais nativos.
//
// Central role (via EventChannel + MethodChannel → Kotlin):
//   - Scan filtrado pelo SERVICE_UUID Sopro (EventChannel ble_scan)
//   - Conexão GATT + leitura do ContextCard (MethodChannel connectAndReadCard)
//
// Peripheral role (via MethodChannel → Kotlin):
//   - Advertising com SERVICE_UUID (BluetoothLeAdvertiser)
//   - GATT server com characteristic de ContextCard (BluetoothGattServer)
//
// Canais Kotlin:
//   MethodChannel "com.sopro.sopro/ble"
//   EventChannel  "com.sopro.sopro/ble_scan"
//
// UUIDs Sopro (FIXOS — nunca alterar):
//   Service:        550e8400-e29b-41d4-a716-446655440000
//   ContextCard ch: 550e8401-e29b-41d4-a716-446655440000
//
// Estratégia de deduplicação:
//   O Android rotaciona o MAC BLE periodicamente (privacidade do SO).
//   _devices é indexado por card.id (UUID estável gerado pelo dono do perfil)
//   após a primeira leitura GATT. Antes disso, usa o MAC como chave temporária.
//   _macToStableId mapeia MAC → ID estável para que eventos de scan subsequentes
//   (com o mesmo ou novo MAC) atualizem a entrada correta.
class BleService {
  static const _bleChannel     = MethodChannel('com.sopro.sopro/ble');
  static const _bleScanChannel = EventChannel('com.sopro.sopro/ble_scan');

  // Indexado por ID estável: card.id se já carregado via GATT, MAC caso contrário.
  // Garante que o mesmo usuário físico aparece uma única vez mesmo após MAC rotation.
  final _devices = <String, DiscoveredSoproUser>{};

  // MAC BLE → ID estável: permite que eventos de scan redetectem dispositivos já
  // conhecidos pelo card.id mesmo que o MAC tenha rotacionado.
  final _macToStableId = <String, String>{};

  // IDs estáveis com fetch GATT em andamento — evita fetches paralelos para o
  // mesmo dispositivo (race condition / vazamento de conexão GATT).
  final _fetchingCards = <String>{};

  // Stream broadcast emitido a cada atualização do cache de dispositivos.
  final _devicesController =
      StreamController<List<DiscoveredSoproUser>>.broadcast();

  // Subscription ao EventChannel de scan nativo
  StreamSubscription<dynamic>? _scanSub;

  // Debounce de 500 ms: agrupa resultados em burst antes de emitir para a UI
  Timer? _emitDebounce;

  // Timer de expiração: verifica a cada 3 s e remove usuários não vistos há >10 s.
  // TTL curto é essencial em ambientes de alto fluxo (eventos, ruas, lojas).
  Timer? _expiryTimer;

  static const _ttl                  = Duration(seconds: 10);
  static const _expiryCheckInterval = Duration(seconds: 3);
  // Refresh de 10s: qualquer atualização de perfil (nome, cargo, WhatsApp, etc.)
  // reflete rapidamente para quem está vendo via BLE na tela de Pessoas Aqui.
  static const _cardRefreshAfter     = Duration(seconds: 10);

  Stream<List<DiscoveredSoproUser>> get devicesStream =>
      _devicesController.stream;

  // ── Permissões BLE ────────────────────────────────────────────────────────

  Future<bool> checkPermissions() async {
    return await _bleChannel.invokeMethod<bool>('checkPermissions') ?? false;
  }

  Future<bool> requestPermissions() async {
    return await _bleChannel.invokeMethod<bool>('requestPermissions') ?? false;
  }

  // ── Estado do adaptador Bluetooth ─────────────────────────────────────────

  Future<bool> isBluetoothOn() async {
    try {
      final state = await _bleChannel.invokeMethod<String>('getAdapterState');
      return state == 'on';
    } on PlatformException {
      return false;
    }
  }

  /// Retorna true se o adaptador Bluetooth do dispositivo está habilitado.
  Future<bool> isBluetoothEnabled() async {
    try {
      return await _bleChannel.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre as configurações de Bluetooth do Android (ACTION_BLUETOOTH_SETTINGS).
  Future<void> openBluetoothSettings() async {
    await _bleChannel.invokeMethod<void>('openBluetoothSettings');
  }

  // ── Scan BLE (central role via EventChannel) ──────────────────────────────

  Future<void> startScan() async {
    if (_scanSub != null) return;

    final correlationId = CorrelationManager.beginOperation('ble_scan');

    _devices.clear();
    _macToStableId.clear();
    _emitDevices();
    _startExpiryTimer();

    _scanSub = _bleScanChannel.receiveBroadcastStream().listen(
      _onScanResult,
      onError: (Object e, StackTrace st) {
        debugPrint('[BleService] Scan error: $e');
        Logger.error('ble_scan_error', payload: {'error': e.toString()},
            exception: e, stackTrace: st,
            feature: 'ble', action: 'scan',
            correlationId: correlationId);
      },
    );
  }

  Future<void> stopScan() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    CorrelationManager.endOperation('ble_scan');
  }

  // Remove entradas não vistas há mais de _ttl a cada _expiryCheckInterval.
  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(_expiryCheckInterval, (_) {
      final cutoff = DateTime.now().subtract(_ttl);
      final expired = _devices.entries
          .where((e) => e.value.lastSeen.isBefore(cutoff))
          .map((e) => e.key)
          .toList();

      if (expired.isNotEmpty) {
        for (final key in expired) {
          final dev = _devices.remove(key);
          _macToStableId.removeWhere((_, v) => v == key);
          if (dev != null && dev.deviceId != key) {
            _macToStableId.remove(dev.deviceId);
          }
          _fetchingCards.remove(key);
        }
        _emitDevices();
      }
    });
  }

  // Processa evento de scan: atualiza ou cria entrada sob ID estável.
  void _onScanResult(dynamic event) {
    final data = Map<String, dynamic>.from(event as Map);
    final mac = data['deviceId'] as String? ?? '';
    if (mac.isEmpty) return;

    final name = (data['deviceName'] as String?) ?? '';
    final rssi = data['rssi'] as int? ?? 0;
    final now  = DateTime.now();

    // Resolve ID estável: card.id se já conhecido via GATT, MAC caso contrário
    final stableId = _macToStableId[mac] ?? mac;
    final existing = _devices[stableId];

    _devices[stableId] = DiscoveredSoproUser(
      deviceId:   mac, // mantém o MAC atual para conexão GATT
      deviceName: name.isNotEmpty
          ? name
          : existing?.deviceName ?? AppStrings.bleUserLabel,
      rssi:       rssi,
      lastSeen:   now,
      card:       existing?.card,
      fetchedAt:  existing?.fetchedAt,
    );
    _macToStableId[mac] = stableId;

    // Agenda re-leitura GATT se card foi carregado há mais de _cardRefreshAfter.
    // Reflete mudanças de privacidade (ex: usuário desativou compartilhamento de WhatsApp).
    _maybeRefreshCard(stableId, now);

    _emitDevices();
  }

  // Re-busca o card via GATT se stale (>30 s). Evita fetch paralelo via _fetchingCards.
  void _maybeRefreshCard(String stableId, DateTime now) {
    final dev = _devices[stableId];
    if (dev == null || dev.card == null || dev.fetchedAt == null) return;
    if (_fetchingCards.contains(stableId)) return;
    if (now.difference(dev.fetchedAt!).inSeconds < _cardRefreshAfter.inSeconds) return;

    _fetchingCards.add(stableId);
    fetchContextCard(dev)
        .then((_) => _fetchingCards.remove(stableId))
        .onError<Object>((e, st) {
      Logger.warn('ble_card_refresh_failed',
          payload: {'stable_id': stableId},
          exception: e, stackTrace: st,
          feature: 'ble', action: 'card_refresh',
          correlationId: CorrelationManager.correlationIdFor('ble_scan'));
      return _fetchingCards.remove(stableId);
    });
  }

  // Emite lista atual com debounce de 500 ms para evitar rebuilds em burst de scan.
  void _emitDevices() {
    _emitDebounce?.cancel();
    _emitDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!_devicesController.isClosed) {
        _devicesController.add(List.unmodifiable(_devices.values.toList()));
      }
    });
  }

  // ── Advertising BLE (peripheral role via MethodChannel) ───────────────────

  // Inicia o advertising com o ContextCard do usuário.
  // [txPower]: nível de potência (0=ULTRA_LOW, 1=LOW, 2=MEDIUM, 3=HIGH).
  // [sharePhone]: se false, omite o campo 'p' do payload mesmo que phone esteja preenchido.
  // Limita bio a 120 chars para manter o payload JSON compacto.
  Future<bool> startAdvertising(
    ContextCardEntity card, {
    int txPower = 1,
    bool sharePhone = true,
  }) async {
    try {
      final payload = jsonEncode({
        'id': card.id,
        'n': card.displayName,
        'r': card.role,
        'c': card.company,
        'b': card.bio.substring(0, min(card.bio.length, 120)),
        't': card.tags,
        // Omite 'p' se o usuário optou por não compartilhar o número
        if (sharePhone && card.phone.isNotEmpty) 'p': card.phone,
      });
      return await _bleChannel.invokeMethod<bool>(
              'startAdvertising', {'cardJson': payload, 'txPower': txPower}) ??
          false;
    } on PlatformException catch (e, st) {
      debugPrint('[BleService] startAdvertising falhou: ${e.message}');
      Logger.warn('ble_advertising_start_failed',
          payload: {'error': e.message},
          exception: e, stackTrace: st,
          feature: 'ble', action: 'advertising_start');
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _bleChannel.invokeMethod<void>('stopAdvertising');
    } on PlatformException catch (e, st) {
      debugPrint('[BleService] stopAdvertising falhou: ${e.message}');
      Logger.warn('ble_advertising_stop_failed',
          payload: {'error': e.message},
          exception: e, stackTrace: st,
          feature: 'ble', action: 'advertising_stop');
    }
  }

  // ── Leitura de ContextCard via GATT (central role via MethodChannel) ──────

  // Conecta ao dispositivo Sopro, lê a characteristic de ContextCard e desconecta.
  // Tenta até 3 vezes (delays de 600ms e 1200ms entre tentativas) para contornar
  // falhas transitórias do Android GATT stack (status=133, service not found).
  // Sanitiza todos os campos recebidos antes de criar a entidade (proteção contra
  // payload malformado ou malicioso).
  Future<DiscoveredSoproUser> fetchContextCard(DiscoveredSoproUser user) async {
    const retryDelays = [Duration(milliseconds: 600), Duration(milliseconds: 1200)];
    PlatformException? lastError;
    final sw = Stopwatch()..start();

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(retryDelays[attempt - 1]);
        debugPrint('[BleService] fetchContextCard retry $attempt/${retryDelays.length} (${user.deviceId})');
      }
      try {
        final cardJson = await _bleChannel.invokeMethod<String>(
          'connectAndReadCard',
          {'deviceId': user.deviceId},
        );
        if (cardJson == null || cardJson.isEmpty) return user;

        // Proteção contra payload JSON inválido — descarta e retorna usuário sem card
        final dynamic raw;
        try {
          raw = jsonDecode(cardJson);
        } catch (e, st) {
          debugPrint('[BleService] fetchContextCard payload JSON inválido (${user.deviceId})');
          Logger.warn('ble_card_json_invalid',
              payload: {'device_id': user.deviceId},
              exception: e, stackTrace: st,
              feature: 'ble', action: 'gatt_parse',
              correlationId: CorrelationManager.correlationIdFor('ble_scan'));
          return user;
        }
        if (raw is! Map) return user;

        final map = raw.cast<String, dynamic>();
        final now = DateTime.now();

        // Sanitiza todos os campos: tipo correto, trim, trunca no limite seguro.
        final cardId = _sanitize(map['id'], maxLength: 36);
        final card = ContextCardEntity(
          // Se o id vier vazio ou malformado, usa o deviceId como fallback
          id:          cardId.isNotEmpty ? cardId : user.deviceId,
          displayName: _sanitize(map['n'], maxLength: 60),
          role:        _sanitize(map['r'], maxLength: 60),
          company:     _sanitize(map['c'], maxLength: 60),
          bio:         _sanitize(map['b'], maxLength: 200),
          tags:        _sanitize(map['t'], maxLength: 100),
          phone:       _sanitize(map['p'], maxLength: 15),
          createdAt:   now,
          updatedAt:   now,
        );

        if (attempt > 0) {
          Logger.info('ble_retry_success', payload: {
            'device_id': user.deviceId,
            'attempt':   attempt + 1,
          }, feature: 'ble', action: 'gatt_retry',
              correlationId: CorrelationManager.correlationIdFor('ble_scan'),
              durationMs: sw.elapsedMilliseconds);
        }

        // Re-indexa de MAC → card.id e lida com MAC rotation
        return _promoteToCardId(user, card, now);
      } on PlatformException catch (e) {
        lastError = e;
        if (attempt < retryDelays.length) {
          debugPrint('[BleService] fetchContextCard tentativa ${attempt + 1} falhou (${user.deviceId}): ${e.message}');
        }
      }
    }

    debugPrint('[BleService] fetchContextCard falhou após ${retryDelays.length + 1} tentativas (${user.deviceId}): ${lastError?.message}');
    Logger.error('ble_gatt_error', payload: {
      'device_id': user.deviceId,
      'message':   lastError?.message ?? 'unknown',
      'attempts':  retryDelays.length + 1,
    }, exception: lastError, feature: 'ble', action: 'gatt_read',
        correlationId: CorrelationManager.correlationIdFor('ble_scan'),
        durationMs: sw.elapsedMilliseconds);
    return user;
  }

  // Reclassifica a entrada de MAC-keyed → card.id-keyed para dedup estável.
  //
  // Casos tratados:
  //   1. Refresh (card.id já é a chave) → atualiza in-place.
  //   2. MAC rotation → outro MAC já registrou este card.id: mescla e remove duplicata.
  //   3. Primeira leitura → promove chave de MAC para card.id.
  DiscoveredSoproUser _promoteToCardId(
    DiscoveredSoproUser user,
    ContextCardEntity card,
    DateTime fetchedAt,
  ) {
    final mac      = user.deviceId;
    final cardId   = card.id;
    final stableId = _macToStableId[mac] ?? mac;

    final updated = DiscoveredSoproUser(
      deviceId:   mac,
      deviceName: card.displayName.isNotEmpty ? card.displayName : user.deviceName,
      rssi:       user.rssi,
      lastSeen:   user.lastSeen,
      card:       card,
      fetchedAt:  fetchedAt,
    );

    if (cardId == stableId) {
      // Caso 1: refresh — chave já é card.id, só atualiza
      _devices[cardId] = updated;
      _emitDevices();
      return updated;
    }

    if (_devices.containsKey(cardId)) {
      // Caso 2: MAC rotation — outro MAC já havia carregado este card.id
      _devices[cardId] = _devices[cardId]!.copyWith(
        deviceId:  mac,
        rssi:      user.rssi,
        lastSeen:  user.lastSeen,
        card:      card,
        fetchedAt: fetchedAt,
      );
    } else {
      // Caso 3: primeira leitura — promove de MAC para card.id
      _devices[cardId] = updated;
    }

    // Remove a entrada temporária com chave MAC
    _devices.remove(stableId);
    _macToStableId.removeWhere((_, v) => v == stableId);
    _macToStableId[mac] = cardId;

    _emitDevices();
    return updated;
  }

  // Sanitiza campo do payload BLE: converte para String, remove espaços extras,
  // trunca no limite. Proteção contra dados malformados ou excessivamente longos.
  static String _sanitize(dynamic value, {required int maxLength}) {
    if (value == null) return '';
    final s = value.toString().trim();
    return s.length > maxLength ? s.substring(0, maxLength) : s;
  }

  // Libera recursos ao descartar o provider
  void dispose() {
    _emitDebounce?.cancel();
    _expiryTimer?.cancel();
    stopScan();
    stopAdvertising();
    _devicesController.close();
  }
}
