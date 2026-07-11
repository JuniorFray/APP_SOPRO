package com.sopro.sopro.logging

import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

// Sink de saída Supabase — envia cada LogEvent como INSERT na tabela app_logs.
//
// Mantém o mesmo contrato HTTP já usado por FloatingVoiceService.logToSupabase()
// e BootReceiver.logToSupabase():
//   endpoint : POST /rest/v1/app_logs
//   campos   : device_id, event_type, payload
//   headers  : apikey, Authorization, Content-Type, Prefer: return=minimal
//
// Integração no pipeline:
//   Logger.emit() → SupabaseSink.onEvent() → executor thread → send() → HTTP
//
// Fire-and-forget: onEvent() é síncrono e retorna imediatamente.
// O envio HTTP ocorre em thread daemon dedicada — sem risco de ANR.
object SupabaseSink : LogSink {

    private const val TAG = "Sopro"
    private const val SUPABASE_URL =
        "https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs"
    private const val SUPABASE_KEY =
        "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"

    // Guard atômico — garante registro único mesmo se register() for chamado
    // concorrentemente (improvável, mas defensivo).
    private val _registered = AtomicBoolean(false)

    // Thread daemon: não impede o processo de encerrar se o app for morto.
    // Single-thread: serializa requests, evita burst de conexões.
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "sopro-supabase-sink").apply { isDaemon = true }
    }

    // Registra este sink no Logger. Idempotente: segunda chamada é no-op.
    // Chamado por SessionManager.init() após installationId estar disponível.
    fun register() {
        if (!_registered.compareAndSet(false, true)) return
        Logger.addSink(this)
    }

    // Chamado por Logger.emit() em qualquer thread.
    // Valida pré-condições e despacha para executor sem bloquear o chamador.
    override fun onEvent(event: LogEvent) {
        val deviceId = SessionManager.installationId
        if (deviceId.isEmpty()) return
        if (!LoggerConfiguration.enableSupabase) return
        executor.execute { send(event, deviceId) }
    }

    // Executa em thread do executor — I/O bloqueante seguro aqui.
    private fun send(event: LogEvent, deviceId: String) {
        val body = try {
            JSONObject().apply {
                put("device_id",  deviceId)
                put("event_type", event.message)
                put("payload",    mapToJson(event.payload ?: emptyMap()))
            }.toString()
        } catch (e: Exception) {
            Log.w(TAG, "[SupabaseSink] serialização falhou para '${event.message}': ${e.message}")
            return
        }

        try {
            val conn = (URL(SUPABASE_URL).openConnection() as HttpURLConnection).apply {
                requestMethod  = "POST"
                connectTimeout = 5_000
                readTimeout    = 5_000
                doOutput       = true
                setRequestProperty("apikey",        SUPABASE_KEY)
                setRequestProperty("Authorization", "Bearer $SUPABASE_KEY")
                setRequestProperty("Content-Type",  "application/json")
                setRequestProperty("Prefer",        "return=minimal")
            }
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (LoggerConfiguration.debugLogging && code != 201) {
                Log.w(TAG, "[SupabaseSink] HTTP $code para '${event.message}'")
            }
            // Consome a resposta para liberar a conexão (mesmo que vazia com return=minimal)
            conn.inputStream.use { it.readBytes() }
            conn.disconnect()
        } catch (e: Exception) {
            // Logging nunca pode crashar o app — falha HTTP é silenciosa em produção
            if (LoggerConfiguration.debugLogging) {
                Log.w(TAG, "[SupabaseSink] HTTP falhou para '${event.message}': ${e.message}")
            }
        }
    }

    // Converte Map<String, Any?> para JSONObject.
    // Preserva Boolean, Int, Long, Double como tipos nativos JSON;
    // demais valores são convertidos via toString() para evitar ClassCastException.
    private fun mapToJson(map: Map<String, Any?>): JSONObject {
        val json = JSONObject()
        map.forEach { (k, v) ->
            when (v) {
                null       -> json.put(k, JSONObject.NULL)
                is Boolean -> json.put(k, v)
                is Int     -> json.put(k, v)
                is Long    -> json.put(k, v)
                is Double  -> json.put(k, v)
                else       -> json.put(k, v.toString())
            }
        }
        return json
    }
}
