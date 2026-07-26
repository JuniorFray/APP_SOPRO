package com.sopro.sopro

import android.content.Context

// OverlayConversationState — Estágio 1 da reorganização do overlay de voz.
//
// Encapsula os "awaiting states" da conversa (aguardando nome, confirmação
// destrutiva, escolha de mercado, etc.), antes soltos como chaves de String
// cruas em SharedPreferences por todo o FloatingVoiceService. Cada estado tem
// get/set (arm*)/clear próprios aqui; o resto do serviço não toca mais nas chaves.
//
// COMPORTAMENTAL-PRESERVADO: mesmo arquivo de prefs, MESMAS chaves, MESMO TTL
// (30 s). Os valores de estado (VAL_AWAITING_*) e o nome do arquivo continuam
// vindo do companion do FloatingVoiceService — aqui só se centraliza a leitura/
// escrita e as chaves de payload que antes eram literais espalhados.
class OverlayConversationState(context: Context) {

    // Mesmo arquivo de estado usado antes (FloatingVoiceService.FLOAT_STATE_PREFS).
    private val prefs = context.getSharedPreferences(
        FloatingVoiceService.FLOAT_STATE_PREFS, Context.MODE_PRIVATE,
    )

    companion object {
        // Chave do timestamp e chaves de payload — antes literais espalhados.
        private const val KEY_AT            = "voice_state_set_at"
        private const val K_TRIGGER_TITLE   = "pending_trigger_title"
        private const val K_TRIGGER_CONTENT = "pending_trigger_content"
        private const val K_TRIGGER_ENV     = "pending_trigger_env"
        private const val K_CONFIRM_INTENT  = "confirm_intent"
        private const val K_CONFIRM_ENV     = "confirm_env"
        private const val K_CONFIRM_TITLE   = "confirm_title"
        private const val K_ENV_NAME        = "pending_env_name"
        private const val K_SHOP_ITEMS      = "pending_shopping_items"
        private const val K_MARKET_NAMES    = "pending_market_names"

        // TTL do estado: expira 30 s após ser gravado (igual ao antigo).
        private const val TTL_MS = 30_000L

        // Valores de estado que eram literais no serviço (não constantes do
        // companion). Mantidos byte-idênticos aos usados nas condições.
        const val AWAITING_ENV_CONFIRM     = "awaiting_env_confirm"
        const val AWAITING_ENV_FOR_TRIGGER = "awaiting_env_for_trigger"
    }

    // ── Leitura do estado corrente ────────────────────────────────────────
    // Capturados uma vez pelo chamador (como os antigos voiceState/stateExpired).
    val current: String? get() = prefs.getString(FloatingVoiceService.KEY_VOICE_STATE, null)
    val isExpired: Boolean get() = System.currentTimeMillis() - prefs.getLong(KEY_AT, 0L) > TTL_MS

    // Payload getters — mesma leitura tolerante (default "" ou null) de antes.
    val pendingTriggerTitle:   String  get() = prefs.getString(K_TRIGGER_TITLE, null) ?: ""
    val pendingTriggerContent: String  get() = prefs.getString(K_TRIGGER_CONTENT, null) ?: ""
    val pendingTriggerEnv:     String  get() = prefs.getString(K_TRIGGER_ENV, null) ?: ""
    val confirmIntent:         String  get() = prefs.getString(K_CONFIRM_INTENT, null) ?: ""
    val confirmEnv:            String  get() = prefs.getString(K_CONFIRM_ENV, null) ?: ""
    val confirmTitle:          String? get() = prefs.getString(K_CONFIRM_TITLE, null)
    val pendingEnvName:        String  get() = prefs.getString(K_ENV_NAME, null) ?: ""
    val pendingShoppingItems:  String  get() = prefs.getString(K_SHOP_ITEMS, null) ?: ""
    val pendingMarketNames:    String  get() = prefs.getString(K_MARKET_NAMES, null) ?: ""

    // clearMarker — remove só estado + timestamp (idêntico à limpeza por expiração
    // do topo de executeVoiceResult, que não mexia nos payloads).
    fun clearMarker() {
        prefs.edit()
            .remove(FloatingVoiceService.KEY_VOICE_STATE).remove(KEY_AT)
            .apply()
    }

    // clear — remove estado + timestamp + TODOS os payloads. Usado ao consumir um
    // estado. remove() de chave ausente é no-op, então é superset seguro das
    // limpezas específicas por branch de antes (só um estado fica armado por vez).
    fun clear() {
        prefs.edit()
            .remove(FloatingVoiceService.KEY_VOICE_STATE).remove(KEY_AT)
            .remove(K_TRIGGER_TITLE).remove(K_TRIGGER_CONTENT).remove(K_TRIGGER_ENV)
            .remove(K_CONFIRM_INTENT).remove(K_CONFIRM_ENV).remove(K_CONFIRM_TITLE)
            .remove(K_ENV_NAME)
            .remove(K_SHOP_ITEMS).remove(K_MARKET_NAMES)
            .apply()
    }

    // ── Setters (arm*) — cada um grava estado + payload + timestamp, exatamente
    //    como os edit() crus que substituem. ─────────────────────────────────

    // Aguardando o nome de um ambiente (sem payload).
    fun armAwaitingName() {
        prefs.edit()
            .putString(FloatingVoiceService.KEY_VOICE_STATE, FloatingVoiceService.VAL_AWAITING_NAME)
            .putLong(KEY_AT, now())
            .apply()
    }

    // Ambiente inexistente: pergunta se cria (com lembrete pendente). [content]
    // omitido = não gravado (paridade com o site que só grava título+ambiente).
    fun armEnvConfirm(title: String?, env: String?, content: String? = null) {
        val e = prefs.edit()
            .putString(K_TRIGGER_TITLE, title)
            .putString(K_TRIGGER_ENV, env)
            .putString(FloatingVoiceService.KEY_VOICE_STATE, AWAITING_ENV_CONFIRM)
            .putLong(KEY_AT, now())
        if (content != null) e.putString(K_TRIGGER_CONTENT, content)
        e.apply()
    }

    // Lembrete sem ambiente: pergunta em qual local salvar.
    fun armEnvForTrigger(title: String?) {
        prefs.edit()
            .putString(K_TRIGGER_TITLE, title)
            .putString(FloatingVoiceService.KEY_VOICE_STATE, AWAITING_ENV_FOR_TRIGGER)
            .putLong(KEY_AT, now())
            .apply()
    }

    // Confirmação destrutiva sim/não. [title] nulo remove a chave (igual ao antigo).
    fun armDestructive(intent: String, env: String, title: String?) {
        val e = prefs.edit()
            .putString(FloatingVoiceService.KEY_VOICE_STATE, FloatingVoiceService.VAL_AWAITING_CONFIRM)
            .putLong(KEY_AT, now())
            .putString(K_CONFIRM_INTENT, intent)
            .putString(K_CONFIRM_ENV, env)
        if (title != null) e.putString(K_CONFIRM_TITLE, title) else e.remove(K_CONFIRM_TITLE)
        e.apply()
    }

    // Confirmar uso do GPS atual ao criar o ambiente pendente.
    fun armLocationConfirm(name: String) {
        prefs.edit()
            .putString(FloatingVoiceService.KEY_VOICE_STATE, FloatingVoiceService.VAL_AWAITING_LOCATION_CONFIRM)
            .putString(K_ENV_NAME, name)
            .putLong(KEY_AT, now())
            .apply()
    }

    // Escolher em qual mercado (2+) os itens pendentes serão gravados. [items] e
    // [names] são as strings já unidas por "|" (mesmo formato de antes).
    fun armMarketChoice(items: String, names: String) {
        prefs.edit()
            .putString(FloatingVoiceService.KEY_VOICE_STATE, FloatingVoiceService.VAL_AWAITING_MARKET_CHOICE)
            .putString(K_SHOP_ITEMS, items)
            .putString(K_MARKET_NAMES, names)
            .putLong(KEY_AT, now())
            .apply()
    }

    private fun now() = System.currentTimeMillis()
}
