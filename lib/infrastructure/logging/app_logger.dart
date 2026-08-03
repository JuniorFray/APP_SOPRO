import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../observability/event_bus.dart';
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

  // Base REST do projeto Supabase (…/rest/v1/). O nome da tabela é concatenado
  // em postToTable — assim o mesmo client/auth atende qualquer tabela nova
  // (app_logs, feedback, …) sem duplicar a infraestrutura HTTP.
  static const supabaseBase =
      'https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/';

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
  static const supabaseApiKey =
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

  // Chaves de CONTEÚDO LIVRE do usuário que nunca podem sair para o Supabase:
  // transcrição da fala, nome de ambiente, título/conteúdo de lembrete, etc.
  // O LogSanitizer não as cobre porque não batem padrões de PII (coord/email/
  // telefone/CPF/token). Aqui elas viram '[REDACTED]' SÓ no caminho Supabase —
  // o console local (dev) já recebeu o payload completo em Logger._emit(), então
  // o valor de debug ("o evento X aconteceu") é preservado sem o conteúdo literal.
  // Espelhado no lado Kotlin em logging/LogRedaction.kt (mesmas chaves).
  static const _supabaseContentDenyKeys = <String>{
    'transcript', 'transcricao', 'environment_name', 'env_name',
    'trigger_title', 'title', 'content', 'name', 'item_name',
    'reply', 'gemini_response', 'speech_result', 'query', 'utterance', 'command',
  };

  // Sink registrado no Logger — converte LogEvent para o formato HTTP existente.
  // Respeita LoggerConfiguration.enableSupabase para desativar em testes.
  // Recebe o payload já sanitizado pelo LogSanitizer dentro do Logger._emit();
  // aplica ainda a redação de conteúdo livre antes do POST (privacidade LGPD).
  static Future<void> _onLogEvent(LogEvent event) async {
    if (_deviceId == null) return;
    if (!LoggerConfiguration.enableSupabase) return;
    await _send(event.message, _redactContentForSupabase(event.payload ?? {}));
  }

  // Substitui por '[REDACTED]' toda chave de conteúdo livre antes do envio ao
  // Supabase. Recursivo (payloads aninhados). Não muta o mapa original — o log
  // local já foi emitido com o conteúdo completo pelo Logger.
  static Map<String, dynamic> _redactContentForSupabase(
    Map<String, dynamic> payload,
  ) {
    return payload.map((key, value) {
      if (_supabaseContentDenyKeys.contains(key.toLowerCase())) {
        return MapEntry(key, '[REDACTED]');
      }
      if (value is Map<String, dynamic>) {
        return MapEntry(key, _redactContentForSupabase(value));
      }
      return MapEntry(key, value);
    });
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
    // Estágio 8 — espelha o evento no Event Bus interno (aditivo; não afeta a
    // telemetria acima). Sem assinantes, é descartado. Cobre as instrumentações
    // do fluxo de voz que passam por AppLogger.log.
    EventBus.instance.publish(AppEvent(
      type: eventType,
      source: 'app_logger',
      payload: payload ?? const {},
    ));
  }

  // Upload do evento na tabela app_logs — monta device_id/event_type/payload e
  // delega o transporte HTTP a postToTable (comportamento idêntico ao original).
  static Future<void> _send(
    String eventType,
    Map<String, dynamic> payload,
  ) {
    return postToTable('app_logs', {
      'device_id': _deviceId,
      'event_type': eventType,
      'payload': payload,
    });
  }

  // POST fire-and-forget genérico a QUALQUER tabela do Supabase (…/rest/v1/<table>).
  // Mesmo client/auth/encoding UTF-8 do logging original — reaproveitável por
  // FeedbackService e futuras integrações. Falhas de rede são silenciosas.
  static Future<void> postToTable(
    String table,
    Map<String, dynamic> body,
  ) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.postUrl(Uri.parse('$supabaseBase$table'));
      request.headers
        ..set('apikey', supabaseApiKey)
        ..set('Authorization', 'Bearer $supabaseApiKey')
        ..contentType = ContentType('application', 'json', charset: 'utf-8')
        ..set('Prefer', 'return=minimal'); // não retorna o registro inserido

      // request.write() usa Latin-1 por padrão no HttpClientRequest,
      // corrompendo acentos (ã→Ã£, í→Ã­, etc.) no Supabase.
      // request.add() com bytes UTF-8 garante encoding correto.
      final bodyBytes = utf8.encode(jsonEncode(body));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      // Em debug, avisa se o Supabase recusou o INSERT (4xx/5xx).
      // Em produção, silencioso — telemetria nunca pode crashar o app.
      if (kDebugMode && response.statusCode != 201) {
        debugPrint(
            '[AppLogger] HTTP ${response.statusCode} ao inserir em "$table"');
      }
      await response.drain<void>(); // consome o body para liberar a conexão
      client.close();
    } catch (e) {
      // Ignora silenciosamente — telemetria não pode crashar o app
      if (kDebugMode) debugPrint('[AppLogger] Falha ao inserir em "$table": $e');
    }
  }
}
