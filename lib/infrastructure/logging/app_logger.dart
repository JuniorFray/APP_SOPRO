import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Registra eventos do app no Supabase de forma assíncrona.
// Nunca bloqueia o app — falhas de rede são silenciosas.
//
// Tipos de eventos logados:
//   app_start      — app iniciado (AppInitializer)
//   geofence_enter — usuário entrou num ambiente (GeofenceManager)
//   geofence_exit  — usuário saiu de um ambiente (GeofenceManager)
//   trigger_fired  — notificação de trigger disparada (FireTriggersUseCase)
//   ble_error      — falha em operação BLE (BleService)
class AppLogger {
  AppLogger._();

  // URL da tabela app_logs no Supabase
  static const _supabaseUrl =
      'https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs';
  // Chave publicável Supabase (só permite INSERT; sem acesso a dados de outros)
  static const _apiKey =
      'sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09';
  // Chave do SharedPreferences para persistir o device ID entre sessões
  static const _deviceIdKey = 'logger_device_id';

  // UUID único por instalação — gerado na primeira execução e persistido
  static String? _deviceId;

  // Inicializa o logger recuperando ou gerando o device ID único.
  // Deve ser chamado uma vez no AppInitializer._init() antes de qualquer log.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
  }

  // Registra um evento sem bloquear o chamador (fire-and-forget).
  // Se init() não foi chamado ainda, o log é descartado silenciosamente.
  static void log(String eventType, [Map<String, dynamic>? payload]) {
    if (_deviceId == null) return;
    _send(eventType, payload ?? {}).ignore();
  }

  static Future<void> _send(
    String eventType,
    Map<String, dynamic> payload,
  ) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.postUrl(Uri.parse(_supabaseUrl));
      request.headers
        ..set('apikey', _apiKey)
        ..set('Authorization', 'Bearer $_apiKey')
        ..contentType = ContentType.json
        ..set('Prefer', 'return=minimal'); // não retorna o registro inserido

      final body = jsonEncode({
        'device_id':  _deviceId,
        'event_type': eventType,
        'payload':    payload,
      });
      request.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close();
      await response.drain<void>(); // consome o body para liberar a conexão
      client.close();
    } catch (e) {
      // Ignora silenciosamente — logging não pode crashar o app
      if (kDebugMode) debugPrint('[AppLogger] Falha ao logar "$eventType": $e');
    }
  }
}
