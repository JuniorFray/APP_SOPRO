import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/context_card_entity.dart';
import '../logging/app_logger.dart';
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
class BleService {
  static const _bleChannel     = MethodChannel('com.sopro.sopro/ble');
  static const _bleScanChannel = EventChannel('com.sopro.sopro/ble_scan');

  // Cache em memória dos usuários detectados nesta sessão de scan.
  // Indexado por deviceId (MAC BLE) — garante deduplicação.
  final _devices = <String, DiscoveredSoproUser>{};

  // Stream broadcast emitido a cada atualização do cache de dispositivos.
  // O debounce em _emitDevices() evita rebuild excessivo quando o scan
  // retorna múltiplos resultados para o mesmo dispositivo em sequência.
  final _devicesController =
      StreamController<List<DiscoveredSoproUser>>.broadcast();

  // Subscription ao EventChannel de scan nativo (ativa/inativa conforme startScan/stopScan)
  StreamSubscription<dynamic>? _scanSub;

  // Timer de debounce: agrupa emissões rápidas em uma única atualização (500ms)
  Timer? _emitDebounce;

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

  // Retorna true se o Bluetooth estiver ligado e disponível
  Future<bool> isBluetoothOn() async {
    try {
      final state = await _bleChannel.invokeMethod<String>('getAdapterState');
      return state == 'on';
    } on PlatformException {
      return false;
    }
  }

  // ── Scan BLE (central role via EventChannel) ──────────────────────────────

  // Inicia o scan BLE assinando o EventChannel nativo.
  // onListen no Kotlin inicia o BluetoothLeScanner com filtro pelo SERVICE_UUID.
  // Cada dispositivo encontrado emite um evento {deviceId, deviceName, rssi}.
  Future<void> startScan() async {
    if (_scanSub != null) return; // scan já ativo

    _devices.clear();
    _emitDevices();

    _scanSub = _bleScanChannel.receiveBroadcastStream().listen(
      _onScanResult,
      onError: (Object e) {
        debugPrint('[BleService] Scan error: $e');
        AppLogger.log('ble_error', {'type': 'scan_error', 'error': e.toString()});
      },
    );
  }

  Future<void> stopScan() async {
    // Cancelar a subscription dispara onCancel no Kotlin, parando o scan nativo
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // Processa um evento de resultado de scan vindo do Kotlin.
  // O Map<String, DiscoveredSoproUser> garante deduplicação por deviceId.
  void _onScanResult(dynamic event) {
    final data = Map<String, dynamic>.from(event as Map);
    final id = data['deviceId'] as String? ?? '';
    if (id.isEmpty) return;

    final name = (data['deviceName'] as String?) ?? '';
    final existing = _devices[id];
    _devices[id] = DiscoveredSoproUser(
      deviceId: id,
      // Preferência: nome do advertisement → nome já conhecido → fallback
      deviceName: name.isNotEmpty ? name : existing?.deviceName ?? 'Usuário Sopro',
      rssi: data['rssi'] as int? ?? 0,
      lastSeen: DateTime.now(),
      card: existing?.card, // preserva ContextCard já carregado via GATT
    );
    _emitDevices();
  }

  // Emite a lista atual de dispositivos com debounce de 500ms.
  // Evita rebuilds excessivos quando o scan retorna resultados em burst
  // (mesmo dispositivo detectado várias vezes em sequência rápida).
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
        'r': card.role,    // cargo
        'c': card.company, // empresa
        'b': card.bio.substring(0, min(card.bio.length, 120)),
        't': card.tags,
        // Omite 'p' se o usuário optou por não compartilhar o número
        if (sharePhone && card.phone.isNotEmpty) 'p': card.phone,
      });
      return await _bleChannel.invokeMethod<bool>(
              'startAdvertising', {'cardJson': payload, 'txPower': txPower}) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[BleService] startAdvertising falhou: ${e.message}');
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _bleChannel.invokeMethod<void>('stopAdvertising');
    } on PlatformException catch (e) {
      debugPrint('[BleService] stopAdvertising falhou: ${e.message}');
    }
  }

  // ── Leitura de ContextCard via GATT (central role via MethodChannel) ──────

  // Conecta ao dispositivo Sopro, lê a characteristic de ContextCard e desconecta.
  // Tenta até 3 vezes (delays de 600ms e 1200ms entre tentativas) para contornar
  // falhas transitórias do Android GATT stack (status=133, service not found).
  // O Kotlin já aguarda 600ms antes do connectGatt e fecha GATTs zumbis antes de cada
  // tentativa. Loga 'ble_retry_success' no Supabase se o retry resolver a falha.
  Future<DiscoveredSoproUser> fetchContextCard(DiscoveredSoproUser user) async {
    const retryDelays = [Duration(milliseconds: 600), Duration(milliseconds: 1200)];
    PlatformException? lastError;

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

        final map = jsonDecode(cardJson) as Map<String, dynamic>;
        final card = ContextCardEntity(
          id: (map['id'] as String?) ?? user.deviceId,
          displayName: (map['n'] as String?) ?? user.deviceName,
          role: (map['r'] as String?) ?? '',
          company: (map['c'] as String?) ?? '',
          bio: (map['b'] as String?) ?? '',
          tags: (map['t'] as String?) ?? '',
          phone: (map['p'] as String?) ?? '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        if (attempt > 0) {
          AppLogger.log('ble_retry_success', {
            'device_id': user.deviceId,
            'attempt':   attempt + 1,
          });
        }

        final updated = user.copyWith(card: card);
        _devices[user.deviceId] = updated;
        _emitDevices();
        return updated;
      } on PlatformException catch (e) {
        lastError = e;
        if (attempt < retryDelays.length) {
          debugPrint('[BleService] fetchContextCard tentativa ${attempt + 1} falhou (${user.deviceId}): ${e.message}');
        }
      }
    }

    debugPrint('[BleService] fetchContextCard falhou após ${retryDelays.length + 1} tentativas (${user.deviceId}): ${lastError?.message}');
    AppLogger.log('ble_error', {
      'type':      'gatt_error',
      'device_id': user.deviceId,
      'message':   lastError?.message ?? 'unknown',
    });
    return user;
  }

  // Libera recursos (scan, advertising, stream) ao descartar o provider
  void dispose() {
    _emitDebounce?.cancel();
    stopScan();
    stopAdvertising();
    _devicesController.close();
  }
}
