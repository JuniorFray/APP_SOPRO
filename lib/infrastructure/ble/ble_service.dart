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

  // Cache em memória dos usuários detectados nesta sessão de scan
  final _devices = <String, DiscoveredSoproUser>{};

  // Stream broadcast emitido a cada atualização do cache de dispositivos
  final _devicesController =
      StreamController<List<DiscoveredSoproUser>>.broadcast();

  // Subscription ao EventChannel de scan nativo (ativa/inativa conforme startScan/stopScan)
  StreamSubscription<dynamic>? _scanSub;

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

  // Processa um evento de resultado de scan vindo do Kotlin
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

  void _emitDevices() {
    if (!_devicesController.isClosed) {
      _devicesController.add(List.unmodifiable(_devices.values.toList()));
    }
  }

  // ── Advertising BLE (peripheral role via MethodChannel) ───────────────────

  // Inicia o advertising com o ContextCard do usuário.
  // Limita bio a 120 chars para manter o payload JSON compacto.
  Future<bool> startAdvertising(ContextCardEntity card) async {
    try {
      final payload = jsonEncode({
        'id': card.id,
        'n': card.displayName,
        'r': card.role,    // cargo
        'c': card.company, // empresa
        'b': card.bio.substring(0, min(card.bio.length, 120)),
        't': card.tags,
      });
      return await _bleChannel.invokeMethod<bool>(
              'startAdvertising', {'cardJson': payload}) ??
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
  // O Kotlin gerencia toda a negociação GATT (MTU, discover, read, cleanup).
  // Retorna o usuário atualizado com o card preenchido; em erro retorna sem alteração.
  Future<DiscoveredSoproUser> fetchContextCard(DiscoveredSoproUser user) async {
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = user.copyWith(card: card);
      _devices[user.deviceId] = updated;
      _emitDevices();
      return updated;
    } on PlatformException catch (e) {
      debugPrint('[BleService] fetchContextCard falhou (${user.deviceId}): ${e.message}');
      AppLogger.log('ble_error', {
        'type':      'gatt_error',
        'device_id': user.deviceId,
        'message':   e.message ?? 'unknown',
      });
      return user;
    }
  }

  // Libera recursos (scan, advertising, stream) ao descartar o provider
  void dispose() {
    stopScan();
    stopAdvertising();
    _devicesController.close();
  }
}
