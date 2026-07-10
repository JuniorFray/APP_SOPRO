package com.sopro.sopro.logging

import org.json.JSONArray
import org.json.JSONObject

// Transforma LogEvent em JSON padronizado — estrutura idêntica ao JsonLogFormatter Flutter.
//
// Estrutura garantida:
// {
//   "schema_version": 1,
//   "timestamp"     : "2026-07-10T15:42:31.552Z",
//   "level"         : "INFO",
//   "message"       : "geofence_enter",
//   "context"       : { ... LogContext.toMap() ... },
//   "payload"       : { ... },        // omitido se null
//   "duration_ms"   : 123,            // omitido se null
//   "exception"     : "...",          // omitido se null
//   "stacktrace"    : "...",          // omitido se null
// }
object JsonFormatter {

    fun format(event: LogEvent): String = buildJsonObject(event).toString()

    fun buildJsonObject(event: LogEvent): JSONObject =
        JSONObject().apply {
            put("schema_version", event.schemaVersion)
            put("timestamp", LogContext.isoMs(event.context.timestamp))
            put("level", event.level.label)
            put("message", event.message)
            put("context", mapToJson(event.context.toMap()))
            event.payload?.let { put("payload", mapToJson(it)) }
            event.durationMs?.let { put("duration_ms", it) }
            event.exception?.let { put("exception", it.toString()) }
            event.stackTraceString?.let { put("stacktrace", it) }
        }

    @Suppress("UNCHECKED_CAST")
    private fun anyToJson(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> mapToJson(value as Map<String, Any?>)
        is List<*> -> listToJson(value)
        is Boolean, is Int, is Long, is Double, is Float -> value
        else -> value.toString()
    }

    private fun mapToJson(map: Map<String, Any?>): JSONObject =
        JSONObject().apply { map.forEach { (k, v) -> put(k, anyToJson(v)) } }

    private fun listToJson(list: List<*>): JSONArray =
        JSONArray().apply { list.forEach { put(anyToJson(it)) } }
}
