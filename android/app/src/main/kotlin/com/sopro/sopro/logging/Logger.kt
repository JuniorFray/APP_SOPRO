package com.sopro.sopro.logging

import android.util.Log
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList

// Contrato de sink de saída. Recebe o LogEvent completo — cada sink extrai
// apenas os campos que precisa. Exceções lançadas de onEvent() são capturadas
// e logadas no Logcat; nunca interrompem o pipeline nem afetam os demais sinks.
fun interface LogSink {
    fun onEvent(event: LogEvent)
}

// Logger principal Kotlin — espelho do Logger Flutter.
//
// Todos os 6 métodos públicos (trace/debug/info/warn/error/fatal) delegam
// ao pipeline único emit(). Nenhuma lógica especial por nível fora de shouldEmit().
//
// Pipeline por evento:
//   1. shouldEmit() — filtra por nível
//   2. LogEvent criado com LogSanitizer aplicado ao payload
//   3. printToConsole() — LogCat (se enableConsole)
//   4. Dispatch para _sinks — independente de enableConsole
//
// Diferença vs Flutter: thread captura Thread.currentThread().name
// (Android é multi-thread; Dart é single-thread por isolate).
//
// Uso:
//   Logger.info("geofence_enter", feature = "geofence", payload = mapOf("id" to envId))
//   Logger.error("ble_gatt_error", exception = e, feature = "ble")
object Logger {

    // Lista de sinks registrados. Thread-safe: CopyOnWriteArrayList permite
    // iteração sem lock enquanto addSink() é raramente chamado.
    private val _sinks = CopyOnWriteArrayList<LogSink>()

    // Registra um sink adicional. Sem deduplicação automática — o chamador é
    // responsável por não registrar o mesmo sink duas vezes (use guard próprio).
    fun addSink(sink: LogSink) = _sinks.add(sink)

    private const val TAG = "Sopro"

    fun trace(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.TRACE, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    fun debug(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.DEBUG, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    fun info(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.INFO, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    fun warn(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.WARN, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    fun error(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.ERROR, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    fun fatal(
        message: String,
        payload: Map<String, Any?>? = null,
        feature: String? = null,
        action: String? = null,
        screen: String? = null,
        method: String? = null,
        correlationId: String? = null,
        exception: Throwable? = null,
        durationMs: Long? = null,
    ) = emit(LogLevel.FATAL, message, payload, feature, action, screen, method, correlationId, exception, durationMs)

    // ── Pipeline único ────────────────────────────────────────────────────────

    private fun emit(
        level: LogLevel,
        message: String,
        payload: Map<String, Any?>?,
        feature: String?,
        action: String?,
        screen: String?,
        method: String?,
        correlationId: String?,
        exception: Throwable?,
        durationMs: Long?,
    ) {
        if (!shouldEmit(level)) return

        val context = LogContext(
            deviceId = SessionManager.installationId,
            installationId = SessionManager.installationId,
            sessionId = SessionManager.sessionId,
            // correlationId explícito tem precedência sobre o CorrelationManager.
            correlationId = correlationId ?: CorrelationManager.currentCorrelationId,
            platform = LoggerConfiguration.platform,
            appVersion = LoggerConfiguration.appVersion,
            buildNumber = LoggerConfiguration.buildNumber,
            feature = feature,
            action = action,
            screen = screen,
            method = method,
            thread = Thread.currentThread().name,
            timestamp = Instant.now(),
        )

        val event = LogEvent(
            schemaVersion = LoggerConfiguration.SCHEMA_VERSION,
            level = level,
            message = message,
            context = context,
            payload = payload?.let { LogSanitizer.sanitize(it) },
            durationMs = durationMs,
            exception = exception,
            stackTraceString = exception?.stackTraceToString(),
        )

        if (LoggerConfiguration.enableConsole) {
            printToConsole(event)
        }

        // Despacha para todos os sinks em sequência. Falha de um sink é isolada:
        // não interrompe os demais. Console e sinks são independentes de enableConsole.
        for (sink in _sinks) {
            try {
                sink.onEvent(event)
            } catch (e: Exception) {
                Log.e(TAG, "[Logger] sink falhou — ${sink::class.simpleName}: ${e.message}")
            }
        }
    }

    // debugLogging == true → nível efetivo é TRACE (tudo passa).
    // debugLogging == false → respeita minimumLevel.
    private fun shouldEmit(level: LogLevel): Boolean {
        val effective = if (LoggerConfiguration.debugLogging) LogLevel.TRACE else LoggerConfiguration.minimumLevel
        return level.ordinal >= effective.ordinal
    }

    private fun printToConsole(event: LogEvent) {
        val androidPriority = when (event.level) {
            LogLevel.TRACE -> Log.VERBOSE
            LogLevel.DEBUG -> Log.DEBUG
            LogLevel.INFO -> Log.INFO
            LogLevel.WARN -> Log.WARN
            LogLevel.ERROR, LogLevel.FATAL -> Log.ERROR
        }
        val msg = if (LoggerConfiguration.enablePrettyPrint) {
            "[${event.level.label}] ${event.message} ${JsonFormatter.format(event)}"
        } else {
            "[${event.level.label}] ${event.message}"
        }
        Log.println(androidPriority, TAG, msg)
    }
}
