package com.sopro.sopro.logging

import android.content.Context
import java.util.UUID

// Gerencia dois identificadores de ciclo de vida — espelho do SessionManager Flutter.
//
//   installation_id — UUID v4 gerado na primeira execução, persistido em SharedPreferences
//                     com chave 'logger_device_id'. Estável entre sessões e reboots.
//
//   session_id      — UUID v4 gerado a cada chamada a init(). Apenas em memória.
//                     Muda a cada abertura; nunca reutilizado entre execuções.
//
// Thread safety: init() usa @Synchronized. Getters leem campos @Volatile.
// Chamadas múltiplas a init() são idempotentes — apenas a primeira executa.
object SessionManager {

    private const val PREFS_NAME = "sopro_logger"
    // Chave idêntica ao Flutter para compatibilidade de installation_id entre camadas.
    private const val INSTALLATION_ID_KEY = "logger_device_id"

    @Volatile private var _installationId: String? = null
    @Volatile private var _sessionId: String? = null

    val installationId: String get() = _installationId ?: ""
    val sessionId: String get() = _sessionId ?: ""
    val isInitialized: Boolean get() = _installationId != null && _sessionId != null

    @Synchronized
    fun init(context: Context) {
        if (isInitialized) return
        _sessionId = UUID.randomUUID().toString()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        _installationId = prefs.getString(INSTALLATION_ID_KEY, null) ?: run {
            val newId = UUID.randomUUID().toString()
            prefs.edit().putString(INSTALLATION_ID_KEY, newId).apply()
            newId
        }
        // Registra o sink Supabase após installationId estar disponível.
        // Idempotente: chamadas subsequentes de SessionManager.init() retornam antes
        // deste ponto (guard isInitialized acima), então register() roda exatamente uma vez.
        SupabaseSink.register()
    }
}
