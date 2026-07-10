import 'package:flutter/foundation.dart';

// Contexto imutável anexado a cada LogEvent.
// Carrega metadados de ambiente, sessão e localização no código — nunca dados
// do usuário final (sem nome, e-mail, coordenadas exatas, etc.).
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

  // Identificador do hardware (para uso futuro com ANDROID_ID).
  // Atualmente igual a installationId.
  final String deviceId;

  // UUID estável por instalação (ver SessionManager).
  final String installationId;

  // UUID efêmero por sessão (ver SessionManager).
  final String sessionId;

  // UUID da operação em andamento (ver CorrelationManager). Pode ser null.
  final String? correlationId;

  // Sistema operacional: 'android', 'ios', etc.
  final String platform;

  // Versão semântica do app (ex.: '0.1.0').
  final String appVersion;

  // Build number (ex.: '1').
  final String buildNumber;

  // Domínio funcional onde o evento ocorreu (ex.: 'voice', 'geofence', 'ble').
  final String? feature;

  // Ação específica dentro da feature (ex.: 'record_start', 'geofence_enter').
  final String? action;

  // Tela ativa no momento do evento (ex.: 'HomeScreen').
  final String? screen;

  // Método/função de origem do evento (ex.: 'resolveIntent').
  final String? method;

  // Thread ou isolate de origem (ex.: 'main', 'background'). Pode ser null.
  final String? thread;

  // Timestamp UTC do momento em que o evento foi criado.
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
        'timestamp': timestamp.toIso8601String(),
      };
}
