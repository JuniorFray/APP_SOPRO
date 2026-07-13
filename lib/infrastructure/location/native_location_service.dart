import 'dart:async';

import 'package:flutter/services.dart';

// Wrapper Dart para os canais nativos expostos por MainActivity.kt.
//
// Usa FusedLocationProviderClient do Android (Google Play Services) via
// MethodChannel (posição pontual + permissão) e EventChannel (stream contínuo).
// Não depende de nenhum pacote pub.dev de GPS — funciona com qualquer Android SDK.
class NativeLocationService {
  static const _method = MethodChannel('com.sopro.sopro/location');
  static const _stream = EventChannel('com.sopro.sopro/location_stream');

  /// Retorna true se ACCESS_FINE_LOCATION já foi concedida.
  Future<bool> checkPermission() async {
    return await _method.invokeMethod<bool>('checkPermission') ?? false;
  }

  /// Abre o diálogo do sistema e aguarda a resposta do usuário.
  /// Retorna true se a permissão foi concedida.
  Future<bool> requestPermission() async {
    return await _method.invokeMethod<bool>('requestPermission') ?? false;
  }

  /// Retorna true se o serviço de localização do dispositivo está habilitado.
  Future<bool> isLocationEnabled() async {
    return await _method.invokeMethod<bool>('isLocationEnabled') ?? false;
  }

  /// Abre as configurações de localização do Android (ACTION_LOCATION_SOURCE_SETTINGS).
  Future<void> openLocationSettings() async {
    await _method.invokeMethod<void>('openLocationSettings');
  }

  /// Abre as configurações do aplicativo (ACTION_APPLICATION_DETAILS_SETTINGS).
  Future<void> openAppSettings() async {
    await _method.invokeMethod<void>('openAppSettings');
  }

  /// Obtém a posição atual do dispositivo (pontual — não inicia monitoramento).
  /// Retorna null se GPS não disponível ou permissão negada.
  Future<({double latitude, double longitude, double accuracy})?> getCurrentPosition() async {
    try {
      final data = await _method.invokeMapMethod<String, dynamic>('getCurrentPosition');
      if (data == null) return null;
      return (
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        accuracy: (data['accuracy'] as num).toDouble(),
      );
    } on PlatformException {
      return null;
    }
  }

  /// Stream contínuo de posições (2 s / 10 m de deslocamento mínimo).
  /// Inclui [accuracy] em metros para ajuste dinâmico do raio de geofence.
  /// Emitido pelo LocationCallback do Kotlin; cancelado ao desinscrever.
  Stream<({double latitude, double longitude, double accuracy})>
      getPositionStream() {
    return _stream.receiveBroadcastStream().map((dynamic data) {
      final map = Map<String, dynamic>.from(data as Map);
      return (
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: (map['accuracy'] as num).toDouble(),
      );
    });
  }
}
