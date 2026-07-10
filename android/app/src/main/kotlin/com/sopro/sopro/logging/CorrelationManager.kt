package com.sopro.sopro.logging

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

// Rastreia correlation IDs por operação nomeada — espelho do CorrelationManager Flutter.
//
// Usa ConcurrentHashMap em vez do Map simples do Flutter porque o lado nativo
// executa em múltiplas threads (main, Binder, WorkManager, etc.).
//
// Ciclo de vida:
//   val id = CorrelationManager.beginOperation("voice")
//   Logger.info("voice_start", correlationId = id)
//   CorrelationManager.endOperation("voice")
object CorrelationManager {

    private val active = ConcurrentHashMap<String, String>()

    // @Volatile garante visibilidade entre threads sem lock completo.
    @Volatile private var lastKey: String? = null

    // Inicia operação rastreável. Retorna o correlationId gerado.
    // Se operationName já existia, substitui o ID anterior.
    fun beginOperation(operationName: String): String {
        val id = UUID.randomUUID().toString()
        active[operationName] = id
        lastKey = operationName
        return id
    }

    // Encerra operação e descarta seu ID. Silencioso se não estava ativa.
    fun endOperation(operationName: String) {
        active.remove(operationName)
        if (lastKey == operationName) {
            lastKey = active.keys().asSequence().lastOrNull()
        }
    }

    // ID da operação específica, ou null se inativa.
    fun correlationIdFor(operationName: String): String? = active[operationName]

    // ID da operação iniciada mais recentemente (compatibilidade com código sem nome).
    val currentCorrelationId: String?
        get() = lastKey?.let { active[it] }

    // Snapshot somente-leitura de todas as operações ativas.
    val activeOperations: Map<String, String>
        get() = HashMap(active)

    // Encerra todas as operações. Use apenas em testes ou reset de estado.
    fun resetAll() {
        active.clear()
        lastKey = null
    }
}
