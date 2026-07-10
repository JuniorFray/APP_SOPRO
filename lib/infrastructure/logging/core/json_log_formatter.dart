import 'dart:convert';

import 'log_event.dart';

// Transforma um LogEvent em representação JSON padronizada.
//
// Estrutura garantida na saída:
//   {
//     "timestamp"   : "2026-07-10T12:00:00.000Z",
//     "level"       : "INFO",
//     "message"     : "geofence_enter",
//     "context"     : { ... LogContext ... },
//     "payload"     : { ... dados do evento ... },   // omitido se null
//     "duration_ms" : 123,                           // omitido se null
//     "exception"   : "FormatException: ...",        // omitido se null
//     "stacktrace"  : "...",                         // omitido se null
//   }
//
// Nunca monta o JSON manualmente — usa jsonEncode para garantir escaping
// correto de caracteres especiais e acentos.
class JsonLogFormatter {
  JsonLogFormatter._();

  // Serializa um LogEvent para string JSON.
  static String format(LogEvent event) => jsonEncode(toMap(event));

  // Converte um LogEvent para Map estruturado (útil para testes e inspeção).
  static Map<String, dynamic> toMap(LogEvent event) => {
        'timestamp': event.context.timestamp.toIso8601String(),
        'level': event.level.label,
        'message': event.message,
        'context': event.context.toMap(),
        if (event.payload != null) 'payload': event.payload,
        if (event.durationMs != null) 'duration_ms': event.durationMs,
        if (event.exception != null) 'exception': event.exception.toString(),
        if (event.stackTrace != null) 'stacktrace': event.stackTrace.toString(),
      };
}
