package com.sopro.sopro.logging

// Redação de CONTEÚDO LIVRE do usuário antes de qualquer POST ao Supabase.
//
// Espelha _supabaseContentDenyKeys do lado Dart (AppLogger): transcrição de fala,
// nome de ambiente, título/conteúdo de lembrete, etc. — dados que o LogSanitizer
// não cobre por não baterem padrões de PII (coordenada/email/telefone/CPF/token).
//
// Aplicada apenas no ponto de egresso (SupabaseSink.send e
// FloatingVoiceService.logToSupabase). O log local (Log.d/logcat em dev) continua
// completo — só o servidor recebe "[REDACTED]", preservando o valor de debug
// ("o evento X aconteceu") sem o conteúdo literal.
object LogRedaction {

    // Mantenha em sincronia com _supabaseContentDenyKeys (app_logger.dart).
    private val DENY_KEYS = setOf(
        "transcript", "transcricao", "environment_name", "env_name",
        "trigger_title", "title", "content", "name", "item_name",
        "reply", "gemini_response", "speech_result", "query", "utterance", "command"
    )

    // Retorna cópia do payload com as chaves de conteúdo substituídas por
    // "[REDACTED]". Comparação case-insensitive. Não muta o mapa original.
    fun redact(payload: Map<String, Any?>): Map<String, Any?> =
        payload.mapValues { (k, v) ->
            if (k.lowercase() in DENY_KEYS) "[REDACTED]" else v
        }
}
