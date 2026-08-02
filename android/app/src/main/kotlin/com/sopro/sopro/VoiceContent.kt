package com.sopro.sopro

import android.content.Context
import org.json.JSONObject

// VoiceContent — fonte UNICA de texto do assistente de voz (prompt de plano +
// frases de persona), compartilhada byte-a-byte com o Home (Dart).
//
// Le o MESMO asset empacotado pelo Flutter: em pubspec ele e "assets/voice/
// voice_content.json"; dentro do APK o Flutter o coloca em
// "flutter_assets/assets/voice/voice_content.json", acessivel pelo AssetManager.
// Assim o overlay nativo (Kotlin puro, sem FlutterEngine) reaproveita o texto sem
// duplica-lo em codigo. Carregado uma vez via [ensureLoaded] no onCreate do
// FloatingVoiceService; OverlayPrompt/OverlayPersona leem deste cache.
object VoiceContent {
    private var planJson: JSONObject? = null
    private var personaJson: JSONObject? = null

    // Le e cacheia o asset. Idempotente. Falha de leitura nao derruba o overlay:
    // os getters caem no fallback "" (o overlay so perde o texto, nao trava).
    fun ensureLoaded(context: Context) {
        if (planJson != null) return
        try {
            val raw = context.assets
                .open("flutter_assets/assets/voice/voice_content.json")
                .bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
            val root = JSONObject(raw)
            planJson = root.getJSONObject("plan")
            personaJson = root.getJSONObject("persona")
        } catch (e: Exception) {
            // silencioso — fallback "" nos getters
        }
    }

    // Segmento do prompt de plano por chave (vazio se ausente/nao carregado).
    fun plan(key: String): String = planJson?.optString(key, "") ?: ""

    // Frase de persona por chave (com {placeholders} ainda por resolver no chamador).
    fun persona(key: String): String = personaJson?.optString(key, "") ?: ""
}
