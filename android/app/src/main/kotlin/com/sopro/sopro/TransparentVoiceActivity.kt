package com.sopro.sopro

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

// TransparentVoiceActivity — activity totalmente transparente que processa ações
// de voz do FloatingVoiceService sem tornar o app visível ao usuário.
//
// Fluxo:
//   FloatingVoiceService → SharedPreferences "sopro_voice" → startActivity(esta)
//   → invokeMethod("processAction") → AppInitializer.dart processa via Drift → finish()
//
// Usa o engine cacheado pela MainActivity (se disponível) para evitar inicialização
// de um segundo engine Dart — garante processamento em < 200 ms.
// Se o engine não estiver cacheado (cold start), FlutterActivity cria um novo
// e o método é enfileirado até o handler Dart ser registrado.
class TransparentVoiceActivity : FlutterActivity() {

    companion object {
        // Chave usada pela MainActivity para guardar o engine no FlutterEngineCache
        internal const val CACHED_ENGINE_ID = "sopro_engine"
    }

    // Reutiliza o engine da MainActivity — já tem AppInitializer rodando com handlers.
    // Retorna null se não há engine cacheado (FlutterActivity cria um novo automaticamente).
    override fun getCachedEngineId(): String? {
        return if (FlutterEngineCache.getInstance().contains(CACHED_ENGINE_ID))
            CACHED_ENGINE_ID
        else
            null
    }

    // NÃO destrói o engine ao encerrar — ele pertence à MainActivity.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val prefs      = getSharedPreferences(VoiceActionReceiver.PREFS_NAME, MODE_PRIVATE)
        val actionJson = prefs.getString(VoiceActionReceiver.KEY_PENDING, null)
        val actionTime = prefs.getLong(VoiceActionReceiver.KEY_PENDING_TIME, 0L)

        val engine = flutterEngine
        if (engine != null
            && actionJson != null
            && System.currentTimeMillis() - actionTime < 30_000L
        ) {
            // Remove da prefs antes de processar — idempotente se activity for recriada
            prefs.edit()
                .remove(VoiceActionReceiver.KEY_PENDING)
                .remove(VoiceActionReceiver.KEY_PENDING_TIME)
                .apply()

            // Envia ao Flutter (engine cacheado já tem o handler do AppInitializer).
            // A activity fecha imediatamente; o engine (cached) processa async em background.
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.sopro.sopro/voice_action")
                .invokeMethod("processAction", actionJson)
        }

        // Fecha independente de sucesso — zero visibilidade para o usuário
        finish()
    }

    // onResume mínimo — apenas repassa ao FlutterActivity sem lógica extra
    override fun onResume() { super.onResume() }
}
