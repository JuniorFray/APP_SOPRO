import 'package:flutter/foundation.dart';

// Contexto imutável anexado a cada LogEvent.
// Carrega metadados de ambiente, sessão e localização no código.
//
// Regra: nunca armazenar dados do usuário final neste objeto —
// sem nome, e-mail, coordenadas exatas ou identificadores pessoais.
// Os IDs (deviceId, installationId) são UUIDs anônimos gerados localmente.
//
// Timestamps: o campo [timestamp] deve SEMPRE ser UTC.
// Use DateTime.now().toUtc() ao construir LogContext.
// A serialização em toMap() garante formato ISO8601 com precisão de
// milissegundos e sufixo 'Z': "2026-07-10T15:42:31.552Z".
@immutable
class LogContext {
  const LogContext({
    required this.deviceId,
    required this.installationId,
    required this.sessionId,
    this.correlationId,
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    this.feature,
    this.action,
    this.screen,
    this.method,
    this.thread,
    required this.timestamp,
  });

  // Identificador do hardware (reservado para uso futuro com ANDROID_ID).
  // Atualmente igual a installationId.
  final String deviceId;

  // UUID estável por instalação (ver SessionManager).
  final String installationId;

  // UUID efêmero por sessão (ver SessionManager).
  final String sessionId;

  // UUID da operação rastreável em andamento (ver CorrelationManager).
  // Null se nenhuma operação foi iniciada ou foi encerrada.
  final String? correlationId;

  // Sistema operacional: 'android', 'ios', etc.
  final String platform;

  // Versão semântica do app (ex.: '0.1.0').
  final String appVersion;

  // Build number (ex.: '1').
  final String buildNumber;

  // Domínio funcional do evento (ex.: 'voice', 'geofence', 'ble').
  final String? feature;

  // Ação específica dentro da feature (ex.: 'record_start', 'geofence_enter').
  final String? action;

  // Tela ativa no momento do evento (ex.: 'HomeScreen').
  final String? screen;

  // Método/função de origem do evento (ex.: 'resolveIntent').
  final String? method;

  // Isolate ou thread de origem (ex.: 'main', 'background'). Pode ser null.
  final String? thread;

  // Momento UTC em que o evento foi criado.
  // DEVE ser DateTime.now().toUtc() — nunca horário local.
  final DateTime timestamp;

  Map<String, dynamic> toMap() => {
        'device_id': deviceId,
        'installation_id': installationId,
        'session_id': sessionId,
        if (correlationId != null) 'correlation_id': correlationId,
        'platform': platform,
        'app_version': appVersion,
        'build_number': buildNumber,
        if (feature != null) 'feature': feature,
        if (action != null) 'action': action,
        if (screen != null) 'screen': screen,
        if (method != null) 'method': method,
        if (thread != null) 'thread': thread,
        'timestamp': _isoMs(timestamp),
      };

  // Formata DateTime como ISO8601 UTC com precisão de milissegundos.
  // Saída garantida: "2026-07-10T15:42:31.552Z"
  // Nunca usa DateTime.toString() que produz formato local não padronizado.
  static String _isoMs(DateTime dt) {
    final u = dt.toUtc();
    return '${_p4(u.year)}-${_p2(u.month)}-${_p2(u.day)}'
        'T${_p2(u.hour)}:${_p2(u.minute)}:${_p2(u.second)}'
        '.${_p3(u.millisecond)}Z';
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');
  static String _p3(int n) => n.toString().padLeft(3, '0');
  static String _p4(int n) => n.toString().padLeft(4, '0');
}
