package com.sopro.sopro.logging

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

// Contexto imutável de ambiente e sessão, idêntico ao LogContext Flutter.
// Regra: sem dados pessoais — deviceId/installationId são UUIDs anônimos.
// timestamp SEMPRE UTC.
data class LogContext(
    val deviceId: String,
    val installationId: String,
    val sessionId: String,
    val correlationId: String?,
    val platform: String,
    val appVersion: String,
    val buildNumber: String,
    val feature: String?,
    val action: String?,
    val screen: String?,
    val method: String?,
    val thread: String?,
    val timestamp: Instant,
) {
    fun toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "device_id" to deviceId,
            "installation_id" to installationId,
            "session_id" to sessionId,
            "platform" to platform,
            "app_version" to appVersion,
            "build_number" to buildNumber,
            "timestamp" to isoMs(timestamp),
        )
        correlationId?.let { map["correlation_id"] = it }
        feature?.let { map["feature"] = it }
        action?.let { map["action"] = it }
        screen?.let { map["screen"] = it }
        method?.let { map["method"] = it }
        thread?.let { map["thread"] = it }
        return map
    }

    companion object {
        // DateTimeFormatter é thread-safe; instância única reutilizada.
        private val FORMATTER: DateTimeFormatter = DateTimeFormatter
            .ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
            .withZone(ZoneOffset.UTC)

        // ISO8601 UTC milissegundos — saída garantida "2026-07-10T15:42:31.552Z".
        fun isoMs(instant: Instant): String = FORMATTER.format(instant)
    }
}
