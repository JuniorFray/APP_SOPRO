package com.sopro.sopro.logging

import com.sopro.sopro.BuildConfig

// Configuração central do sistema de logging Kotlin — espelho do LoggerConfiguration Flutter.
// Todos os campos mutáveis para permitir ajuste em runtime.
object LoggerConfiguration {

    // Versão do schema JSON. Incrementar apenas em mudanças incompatíveis de formato.
    const val SCHEMA_VERSION: Int = 1

    // Ativa TRACE/DEBUG e desabilita mascaramento de campos de diagnóstico.
    // Padrão: BuildConfig.DEBUG (true em debug, false em release).
    var debugLogging: Boolean = BuildConfig.DEBUG

    // Nível mínimo fora do modo debug. Em debug, nível efetivo é sempre TRACE.
    var minimumLevel: LogLevel = LogLevel.INFO

    // Habilita envio ao Supabase (fase futura — reservado para AppLogger Kotlin).
    var enableSupabase: Boolean = true

    // Habilita saída no Logcat via android.util.Log.
    var enableConsole: Boolean = BuildConfig.DEBUG

    // Inclui JSON formatado na linha do Logcat (verbose, somente em debug).
    var enablePrettyPrint: Boolean = BuildConfig.DEBUG

    // Aplica LogSanitizer sobre o payload antes de qualquer saída.
    var enableDataMasking: Boolean = true

    // ── Fase futura: fila e retry ─────────────────────────────────────────────
    var maxQueueSize: Int = 100
    var batchSize: Int = 10
    var retryAttempts: Int = 3

    // ── Metadados do app ─────────────────────────────────────────────────────
    var appVersion: String = "0.1.0"
    var buildNumber: String = "1"
    var platform: String = "android"
}
