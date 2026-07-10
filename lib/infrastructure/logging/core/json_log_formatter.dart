import 'dart:convert';

import 'log_event.dart';

// Transforma um LogEvent em representação JSON padronizada.
//
// ── Estrutura garantida na saída ──────────────────────────────────────────
// {
//   "schema_version": 1,                           // sempre presente; ver LoggerConfiguration.schemaVersion
//   "timestamp"     : "2026-07-10T15:42:31.552Z",  // ISO8601 UTC, milissegundos
//   "level"         : "INFO",
//   "message"       : "geofence_enter",
//   "context"       : { ... LogContext.toMap() ... },
//   "payload"       : { ... dados do evento ... },   // omitido se null
//   "duration_ms"   : 123,                           // omitido se null
//   "exception"     : "FormatException: ...",        // omitido se null
//   "stacktrace"    : "...",                         // omitido se null
// }
//
// ── Garantias de serialização ─────────────────────────────────────────────
// • Nunca usa DateTime.toString() — produz formato local, não padronizado.
// • Todos os timestamps são UTC com precisão de milissegundos (3 casas).
// • jsonEncode garante escaping correto de caracteres especiais e acentos.
// • Campos null são omitidos (JSON mínimo, sem chaves desnecessárias).
class JsonLogFormatter {
  JsonLogFormatter._();

  // Serializa um LogEvent para string JSON.
  static String format(LogEvent event) => jsonEncode(toMap(event));

  // Converte um LogEvent para Map estruturado.
  // Útil para testes unitários e inspeção sem serialização completa.
  static Map<String, dynamic> toMap(LogEvent event) => {
        'schema_version': event.schemaVersion,
        'timestamp': _isoMs(event.context.timestamp),
        'level': event.level.label,
        'message': event.message,
        'context': event.context.toMap(),
        if (event.payload != null) 'payload': event.payload,
        if (event.durationMs != null) 'duration_ms': event.durationMs,
        if (event.exception != null) 'exception': event.exception.toString(),
        if (event.stackTrace != null) 'stacktrace': event.stackTrace.toString(),
      };

  // ISO8601 UTC com precisão de milissegundos.
  // Exemplo: "2026-07-10T15:42:31.552Z"
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
