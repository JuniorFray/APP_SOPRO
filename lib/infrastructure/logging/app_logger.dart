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

  // Chave publishable do Supabase — projetada para ser embutida em apps cliente.
  //
  // O prefixo "sb_publishable_" é análogo ao firebase_options.dart do Firebase:
  // não é um secret key e não concede acesso admin. Pode estar no fonte.
  //
  // A segurança real depende da política RLS na tabela app_logs (painel Supabase):
  //   INSERT: permitido com esta chave.
  //   SELECT/UPDATE/DELETE: bloqueados — nenhum dispositivo lê logs de outros.
  //
  // Nenhum dado pessoal é enviado: apenas event_type, environment_id e erros —
  // sem coordenadas exatas, nomes, telefones ou identificadores de usuário.
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
      // Em debug, avisa se o Supabase recusou o log (4xx/5xx).
      // Em produção, silencioso — logging nunca pode crashar o app.
      if (kDebugMode && response.statusCode != 201) {
        debugPrint('[AppLogger] HTTP ${response.statusCode} ao logar "$eventType"');
      }
      await response.drain<void>(); // consome o body para liberar a conexão
      client.close();
    } catch (e) {
      // Ignora silenciosamente — logging não pode crashar o app
      if (kDebugMode) debugPrint('[AppLogger] Falha ao logar "$eventType": $e');
    }
  }
}
