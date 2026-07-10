import 'package:flutter/foundation.dart';

import 'correlation_manager.dart';
import 'json_log_formatter.dart';
import 'log_context.dart';
import 'log_event.dart';
import 'log_level.dart';
import 'log_sanitizer.dart';
import 'logger_configuration.dart';
import 'session_manager.dart';

// Logger principal do Sopro.
//
// ── Responsabilidades (fase atual) ───────────────────────────────────────
//   1. Receber chamadas de log com level, message e contexto opcional.
//   2. Filtrar pelo nível mínimo configurado (LoggerConfiguration.minimumLevel).
//   3. Criar LogEvent estruturado com LogContext completo.
//   4. Aplicar LogSanitizer sobre o payload.
//   5. Formatar via JsonLogFormatter e emitir no console (se habilitado).
//
// ── Fora do escopo desta fase ────────────────────────────────────────────
//   • Fila de eventos e envio em lote ao Supabase (permanece em AppLogger).
//   • Retry automático por falha de rede.
//
// ── Pipeline único ───────────────────────────────────────────────────────
// Todos os 6 métodos públicos (trace/debug/info/warn/error/fatal) passam
// pelo mesmo método privado _emit(), garantindo comportamento idêntico
// independentemente do nível. Não existe lógica especial por nível fora de
// _shouldEmit() e da comparação com LoggerConfiguration.minimumLevel.
//
// ── Correlation ID ───────────────────────────────────────────────────────
// Cada método aceita o parâmetro opcional [correlationId]. Se fornecido,
// substitui o ID do CorrelationManager. Use quando múltiplos fluxos
// simultâneos precisam rastrear eventos independentemente:
//   final id = CorrelationManager.beginOperation('voice');
//   Logger.info('voice_start', correlationId: id);
class Logger {
  Logger._();

  // Rastreamento interno de fluxo. Suprimido em produção.
  static void trace(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.trace, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // Informações de diagnóstico úteis durante desenvolvimento. Suprimido em produção.
  static void debug(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.debug, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // Eventos operacionais normais (app_start, geofence_enter, trigger_fired…).
  static void info(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.info, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // Situações inesperadas que não interrompem o fluxo mas merecem atenção.
  static void warn(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.warn, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // Falhas recuperáveis (ble_error, photon_http_error, notification_error…).
  static void error(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.error, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // Falhas críticas que comprometem a operação do app.
  static void fatal(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(LogLevel.fatal, message,
          payload: payload, feature: feature, action: action,
          screen: screen, method: method, correlationId: correlationId,
          exception: exception, stackTrace: stackTrace, durationMs: durationMs);

  // ── Pipeline interno único ────────────────────────────────────────────────

  static void _emit(
    LogLevel level,
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    String? correlationId,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) {
    if (!_shouldEmit(level)) return;

    final event = LogEvent(
      schemaVersion: LoggerConfiguration.schemaVersion,
      level: level,
      message: message,
      context: LogContext(
        deviceId: SessionManager.installationId,
        installationId: SessionManager.installationId,
        sessionId: SessionManager.sessionId,
        // correlationId explícito tem precedência sobre o CorrelationManager.
        correlationId: correlationId ?? CorrelationManager.currentCorrelationId,
        platform: LoggerConfiguration.platform,
        appVersion: LoggerConfiguration.appVersion,
        buildNumber: LoggerConfiguration.buildNumber,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        thread: null,
        timestamp: DateTime.now().toUtc(),
      ),
      payload: payload != null ? LogSanitizer.sanitize(payload) : null,
      durationMs: durationMs,
      exception: exception,
      stackTrace: stackTrace,
    );

    if (LoggerConfiguration.enableConsole) {
      _printToConsole(event);
    }
  }

  // Filtragem por nível:
  //   • debugLogging == true  → nível efetivo mínimo é trace (tudo passa).
  //   • debugLogging == false → nível efetivo mínimo é minimumLevel.
  // A comparação usa o índice do enum, que segue a ordem de severidade:
  //   trace(0) < debug(1) < info(2) < warn(3) < error(4) < fatal(5)
  static bool _shouldEmit(LogLevel level) {
    final effective = LoggerConfiguration.debugLogging
        ? LogLevel.trace
        : LoggerConfiguration.minimumLevel;
    return level.index >= effective.index;
  }

  static void _printToConsole(LogEvent event) {
    if (LoggerConfiguration.enablePrettyPrint) {
      debugPrint(
        '[Sopro][${event.level.label}] ${event.message} '
        '${JsonLogFormatter.format(event)}',
      );
    } else {
      debugPrint('[Sopro][${event.level.label}] ${event.message}');
    }
  }
}
