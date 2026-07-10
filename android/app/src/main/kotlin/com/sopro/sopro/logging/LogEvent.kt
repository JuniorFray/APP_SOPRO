package com.sopro.sopro.logging

// Modelo completo de um evento de log — espelho do LogEvent Flutter.
// Criado pelo Logger, consumido pelo JsonFormatter e sinks de saída.
data class LogEvent(
    // Versão do schema JSON. Nunca preencher manualmente — Logger injeta via LoggerConfiguration.
    val schemaVersion: Int,
    val level: LogLevel,
    val message: String,
    val context: LogContext,
    // Payload já sanitizado por LogSanitizer antes de chegar aqui.
    val payload: Map<String, Any?>?,
    val durationMs: Long?,
    val exception: Throwable?,
    // Pré-serializado para evitar recalcular em cada sink de saída.
    val stackTraceString: String?,
)
