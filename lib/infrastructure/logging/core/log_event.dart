import 'log_context.dart';
import 'log_level.dart';

// Modelo completo de um evento de log.
// Criado pelo Logger e consumido pelo JsonLogFormatter e pelas sinks de saída.
class LogEvent {
  const LogEvent({
    required this.level,
    required this.message,
    required this.context,
    this.payload,
    this.durationMs,
    this.exception,
    this.stackTrace,
  });

  // Severidade do evento.
  final LogLevel level;

  // Mensagem principal — normalmente o event_type (ex.: 'geofence_enter').
  final String message;

  // Contexto de ambiente e sessão no momento do evento.
  final LogContext context;

  // Dados adicionais estruturados associados ao evento.
  // Já sanitizados pelo LogSanitizer antes de chegar aqui.
  final Map<String, dynamic>? payload;

  // Duração da operação em milissegundos (para eventos com tempo mensurável).
  final int? durationMs;

  // Exceção capturada, se o evento representa um erro.
  final Object? exception;

  // Stack trace associado à exceção.
  final StackTrace? stackTrace;
}
