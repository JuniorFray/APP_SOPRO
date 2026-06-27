import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/entities/context_card_entity.dart';
import 'discovered_sopro_user.dart';

// BleService gerencia toda a comunicação BLE do Sopro:
//
// Central role (via flutter_blue_plus):
//   - Scan filtrando pelo SERVICE_UUID Sopro
//   - Conexão GATT e leitura do ContextCard de usuários detectados
//
// Peripheral role (via MethodChannel → MainActivity.kt):
//   - Advertising com SERVICE_UUID para ser visível a outros usuários Sopro
//   - GATT server expondo o próprio ContextCard via characteristic
//
// UUID Sopro (FIXO):
//   Service:        550e8400-e29b-41d4-a716-446655440000
//   ContextCard ch: 550e8401-e29b-41d4-a716-446655440000
class BleService {
  static const _bleChannel = MethodChannel('com.sopro.sopro/ble');

  // UUID do serviço Sopro — identifica o app na rede BLE (FIXO, nunca alterar)
  static final _serviceUuid = Guid('550e8400-e29b-41d4-a716-446655440000');

  // UUID da characteristic que retorna o ContextCard em JSON UTF-8
  static final _cardCharUuid = Guid('550e8401-e29b-41d4-a716-446655440000');

  // Cache em memória dos usuários detectados nesta sessão de scan
  final _devices = <String, DiscoveredSoproUser>{};

  // Broadcast stream — emitido a cada atualização do scan
  final _devicesController =
      StreamController<List<DiscoveredSoproUser>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;

  Stream<List<DiscoveredSoproUser>> get devicesStream =>
      _devicesController.stream;

  bool get isScanning => FlutterBluePlus.isScanningNow;

  // ── Permissões BLE (via MethodChannel → Kotlin) ─────────────────────────

  Future<bool> checkPermissions() async {
    return await _bleChannel.invokeMethod<bool>('checkPermissions') ?? false;
  }

  Future<bool> requestPermissions() async {
    return await _bleChannel.invokeMethod<bool>('requestPermissions') ?? false;
  }

  // ── Scan (central role via flutter_blue_plus) ────────────────────────────

  // Inicia o scan BLE filtrando pelo SERVICE_UUID Sopro.
  // Apenas dispositivos que anunciam o UUID aparecem na lista — evita ruído
  // de outros dispositivos Bluetooth próximos.
  Future<void> startScan() async {
    if (FlutterBluePlus.isScanningNow) return;

    _devices.clear();
    _emitDevices();

    // Escuta os resultados emitidos pelo flutter_blue_plus
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final existing = _devices[id];
        _devices[id] = DiscoveredSoproUser(
          deviceId: id,
          // advName vem do pacote de advertisement; fallback para nome já conhecido
          deviceName: r.device.advName.isNotEmpty
              ? r.device.advName
              : existing?.deviceName ?? 'Usuário Sopro',
          rssi: r.rssi,
          lastSeen: DateTime.now(),
          card: existing?.card, // preserva ContextCard já carregado
        );
      }
      _emitDevices();
    });

    await FlutterBluePlus.startScan(
      withServices: [_serviceUuid],
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void _emitDevices() {
    if (!_devicesController.isClosed) {
      _devicesController.add(List.unmodifiable(_devices.values.toList()));
    }
  }

  // ── Advertising (peripheral role via MethodChannel) ─────────────────────

  // Inicia o advertising com o ContextCard do usuário.
  // Limita bio a 120 chars para reduzir o payload JSON transmitido via GATT.
  Future<bool> startAdvertising(ContextCardEntity card) async {
    try {
      final payload = jsonEncode({
        'id': card.id,
        'n': card.displayName,
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

  // ── Leitura de ContextCard via GATT (central role) ──────────────────────

  // Conecta ao dispositivo, lê a characteristic do ContextCard e retorna
  // o usuário atualizado. Em caso de erro retorna o usuário sem alteração.
  Future<DiscoveredSoproUser> fetchContextCard(DiscoveredSoproUser user) async {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(user.deviceId));
    try {
      // license: License.nonprofit = uso pessoal/educacional (FlutterBluePlus License)
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();

      // Procura o serviço Sopro na lista de serviços descobertos
      BluetoothService? soproService;
      for (final s in services) {
        if (s.serviceUuid == _serviceUuid) {
          soproService = s;
          break;
        }
      }
      if (soproService == null) {
        debugPrint('[BleService] Serviço Sopro não encontrado em ${user.deviceId}');
        return user;
      }

      // Procura a characteristic de ContextCard dentro do serviço
      BluetoothCharacteristic? cardChar;
      for (final c in soproService.characteristics) {
        if (c.characteristicUuid == _cardCharUuid) {
          cardChar = c;
          break;
        }
      }
      if (cardChar == null) {
        debugPrint('[BleService] Characteristic de ContextCard não encontrada');
        return user;
      }

      // Lê os bytes — flutter_blue_plus lida com Long Read automaticamente
      final bytes = await cardChar.read();
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final card = ContextCardEntity(
        id: (map['id'] as String?) ?? user.deviceId,
        displayName: (map['n'] as String?) ?? user.deviceName,
        bio: (map['b'] as String?) ?? '',
        tags: (map['t'] as String?) ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Atualiza o cache com o card carregado e re-emite a lista
      final updated = user.copyWith(card: card);
      _devices[user.deviceId] = updated;
      _emitDevices();
      return updated;
    } catch (e) {
      debugPrint('[BleService] Erro ao buscar ContextCard de ${user.deviceId}: $e');
      return user;
    } finally {
      // Desconecta independente de sucesso ou erro
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // Libera recursos quando o provider for descartado
  void dispose() {
    stopScan();
    stopAdvertising();
    _devicesController.close();
  }
}
