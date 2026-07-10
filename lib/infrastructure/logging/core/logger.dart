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
// Responsabilidades nesta fase:
//   - Criar LogEvent estruturado para cada chamada de log.
//   - Aplicar LogSanitizer sobre o payload.
//   - Formatar e emitir no console (se enableConsole == true).
//
// Fora do escopo desta fase (implementados em fases futuras):
//   - Fila de eventos (maxQueueSize / batchSize).
//   - Envio direto ao Supabase (permanece em AppLogger._send()).
//   - Retry automático (retryAttempts).
//
// Todos os métodos são estáticos para manter a mesma ergonomia do AppLogger
// legado e evitar injeção de dependência onde não é necessária.
class Logger {
  Logger._();

  // Nível mais granular — apenas para rastreamento interno de fluxo.
  static void trace(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.trace,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // Informações de diagnóstico úteis durante desenvolvimento.
  static void debug(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.debug,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // Eventos operacionais normais (app_start, geofence_enter, trigger_fired…).
  static void info(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.info,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // Situações inesperadas que não interrompem o fluxo mas merecem atenção.
  static void warn(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.warn,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // Falhas recuperáveis (ble_error, photon_http_error, notification_error…).
  static void error(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.error,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // Falhas críticas que comprometem a operação do app.
  static void fatal(
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) =>
      _emit(
        LogLevel.fatal,
        message,
        payload: payload,
        feature: feature,
        action: action,
        screen: screen,
        method: method,
        exception: exception,
        stackTrace: stackTrace,
        durationMs: durationMs,
      );

  // ─── Implementação interna ────────────────────────────────────────────────

  static void _emit(
    LogLevel level,
    String message, {
    Map<String, dynamic>? payload,
    String? feature,
    String? action,
    String? screen,
    String? method,
    Object? exception,
    StackTrace? stackTrace,
    int? durationMs,
  }) {
    if (!_shouldEmit(level)) return;

    final sanitized =
        payload != null ? LogSanitizer.sanitize(payload) : null;

    final event = LogEvent(
      level: level,
      message: message,
      context: LogContext(
        deviceId: SessionManager.installationId,
        installationId: SessionManager.installationId,
        sessionId: SessionManager.sessionId,
        correlationId: CorrelationManager.currentCorrelationId,
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
      payload: sanitized,
      durationMs: durationMs,
      exception: exception,
      stackTrace: stackTrace,
    );

    if (LoggerConfiguration.enableConsole) {
      _printToConsole(event);
    }
  }

  // trace e debug são suprimidos fora do modo debug para reduzir ruído.
  static bool _shouldEmit(LogLevel level) {
    if (!LoggerConfiguration.debugLogging &&
        (level == LogLevel.trace || level == LogLevel.debug)) {
      return false;
    }
    return true;
  }

  static void _printToConsole(LogEvent event) {
    if (LoggerConfiguration.enablePrettyPrint) {
      final json = JsonLogFormatter.format(event);
      debugPrint('[Sopro][${event.level.label}] ${event.message} $json');
    } else {
      debugPrint('[Sopro][${event.level.label}] ${event.message}');
    }
  }
}
