import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'core/log_event.dart';
import 'core/logger.dart';
import 'core/logger_configuration.dart';
import 'core/session_manager.dart';

// Fachada (Facade) de compatibilidade retroativa sobre o novo Logger.
//
// Todas as chamadas AppLogger.log() e AppLogger.init() espalhadas pelo projeto
// continuam funcionando sem alteração — AppLogger delega para o Logger
// estruturado e mantém o upload Supabase inalterado nesta fase.
//
// Fluxo de uma chamada AppLogger.log(eventType, payload):
//   1. Logger.info(eventType, payload: payload)
//        → cria LogEvent estruturado
//        → aplica LogSanitizer
//        → emite no console (se habilitado)
//   2. _send(eventType, payload)
//        → upload fire-and-forget ao Supabase (inalterado)
//
// Tipos de eventos logados:
//   app_start            — app iniciado (AppInitializer)
//   geofence_enter       — usuário entrou num ambiente (GeofenceManager)
//   geofence_exit        — usuário saiu de um ambiente (GeofenceManager)
//   trigger_fired        — notificação de trigger disparada (FireTriggersUseCase)
//   ble_error            — falha em operação BLE (BleService)
//   voice_debug          — diagnóstico de intenção de voz (VoiceService)
//   stale_prefs_reset    — reset de prefs inconsistentes (AppInitializer)
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

  // installation_id persistido — alimentado pelo SessionManager após init().
  // Mantido aqui para uso exclusivo de _onLogEvent() sem alterar a assinatura HTTP.
  static String? _deviceId;

  // Garante que o sink Supabase seja registrado no Logger apenas uma vez,
  // mesmo que AppLogger.init() seja chamado em múltiplos isolates/locais.
  static bool _sinkRegistered = false;

  // Inicializa o logger:
  //   1. Delega ao SessionManager (persiste installation_id, gera session_id).
  //   2. Popula _deviceId para que _send() continue funcionando.
  //
  // Deve ser chamado uma vez no AppInitializer._init() antes de qualquer log.
  static Future<void> init() async {
    await SessionManager.init();
    _deviceId = SessionManager.installationId;
    if (!_sinkRegistered) {
      Logger.addSink(_onLogEvent);
      _sinkRegistered = true;
    }
  }

  // Sink registrado no Logger — converte LogEvent para o formato HTTP existente.
  // Respeita LoggerConfiguration.enableSupabase para desativar em testes.
  // Recebe o payload já sanitizado pelo LogSanitizer dentro do Logger._emit().
  static Future<void> _onLogEvent(LogEvent event) async {
    if (_deviceId == null) return;
    if (!LoggerConfiguration.enableSupabase) return;
    await _send(event.message, event.payload ?? {});
  }

  // Registra um evento sem bloquear o chamador (fire-and-forget).
  //
  // Encaminha para Logger.info() para logging estruturado, e em seguida
  // para _send() para persistência no Supabase.
  // Se init() não foi chamado ainda, o log é descartado silenciosamente.
  static void log(String eventType, [Map<String, dynamic>? payload]) {
    if (_deviceId == null) return;
    Logger.info(eventType, payload: payload);
    // _send() removido — Logger._emit() despacha para _onLogEvent() via sink
  }

  // Upload HTTP fire-and-forget ao Supabase — inalterado em relação à
  // implementação original. Falhas de rede são silenciosas em produção.
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
        'device_id': _deviceId,
        'event_type': eventType,
        'payload': payload,
      });
      request.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close();
      // Em debug, avisa se o Supabase recusou o log (4xx/5xx).
      // Em produção, silencioso — logging nunca pode crashar o app.
      if (kDebugMode && response.statusCode != 201) {
        debugPrint(
            '[AppLogger] HTTP ${response.statusCode} ao logar "$eventType"');
      }
      await response.drain<void>(); // consome o body para liberar a conexão
      client.close();
    } catch (e) {
      // Ignora silenciosamente — logging não pode crashar o app
      if (kDebugMode) debugPrint('[AppLogger] Falha ao logar "$eventType": $e');
    }
  }
}
