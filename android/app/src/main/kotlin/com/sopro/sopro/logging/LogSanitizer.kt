package com.sopro.sopro.logging

// Mascaramento automático de payloads — comportamento idêntico ao LogSanitizer Flutter.
//
// Duas camadas:
//   Camada 1a — chave sensível → valor inteiro substituído por "[REDACTED]"
//   Camada 1b — chave geográfica → substituído por "[LOCATION]"
//   Camada 2  — conteúdo de string: JWT, Bearer, e-mail, CPF, telefone, URL params
//
// Isenções em modo debug (debugLogging == true):
//   transcript, environment_name, gemini_response, intent, speech_result
//   → necessários para diagnóstico de voz e NLU.
@Suppress("UNCHECKED_CAST")
object LogSanitizer {

    private val debugExemptKeys = setOf(
        "transcript",
        "environment_name",
        "gemini_response",
        "intent",
        "speech_result",
    )

    private val sensitiveKeyPattern = Regex(
        """^(?:authorization|apikey|api_key|token|bearer|password|senha|""" +
            """cookie|secret|private_key|access_key|refresh_token|""" +
            """supabase_key|gemini_key|user_id|uid|account_id|profile_id|person_id)$""",
        RegexOption.IGNORE_CASE,
    )

    // \b evita falsos positivos em "platform" (contém "lat"?) ou "relations".
    private val locationKeyPattern = Regex(
        """\blat(?:itude)?\b|\blon(?:gitude)?\b|\blng\b""",
        RegexOption.IGNORE_CASE,
    )

    private val jwtPattern = Regex("""eyJ[\w\-]+\.eyJ[\w\-]+\.[\w\-]+""")
    private val bearerPattern = Regex("""Bearer\s+\S+""", RegexOption.IGNORE_CASE)
    private val emailPattern = Regex("""\b[\w.\-]+@[\w.\-]+\.\w{2,}\b""")
    private val cpfPattern = Regex("""\b\d{3}\.\d{3}\.\d{3}-\d{2}\b""")
    private val phonePattern = Regex(
        """\b(?:\+55\s?)?(?:\(?\d{2}\)?[\s\-]?)(?:9\s?)?\d{4}[\-\s]?\d{4}\b""",
    )
    private val urlTokenPattern = Regex(
        """([?&](?:token|api_key|apikey|access_token|key|secret|auth|authorization|bearer)=)[^&\s]+""",
        RegexOption.IGNORE_CASE,
    )

    // Ponto de entrada público. Retorna payload original se mascaramento desabilitado.
    fun sanitize(payload: Map<String, Any?>): Map<String, Any?> {
        if (!LoggerConfiguration.enableDataMasking) return payload
        return sanitizeMap(payload)
    }

    private fun sanitizeMap(map: Map<String, Any?>): Map<String, Any?> =
        map.mapValues { (key, value) ->
            val isExempt = LoggerConfiguration.debugLogging &&
                debugExemptKeys.contains(key.lowercase())
            if (isExempt) return@mapValues value

            if (sensitiveKeyPattern.matches(key.lowercase())) return@mapValues "[REDACTED]"
            if (locationKeyPattern.containsMatchIn(key)) return@mapValues "[LOCATION]"

            sanitizeValue(value)
        }

    private fun sanitizeValue(value: Any?): Any? = when (value) {
        is String -> sanitizeString(value)
        is Map<*, *> -> sanitizeMap(value as Map<String, Any?>)
        is List<*> -> value.map { sanitizeValue(it) }
        else -> value
    }

    private fun sanitizeString(value: String): String {
        var result = value
        result = jwtPattern.replace(result, "[JWT]")
        result = bearerPattern.replace(result, "Bearer [REDACTED]")
        result = urlTokenPattern.replace(result) { mr -> "${mr.groupValues[1]}[REDACTED]" }
        result = emailPattern.replace(result, "[EMAIL]")
        result = cpfPattern.replace(result, "[CPF]")
        result = phonePattern.replace(result, "[PHONE]")
        return result
    }
}
