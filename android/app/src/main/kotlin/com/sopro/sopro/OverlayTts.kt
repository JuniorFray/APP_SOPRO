package com.sopro.sopro

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import java.io.File
import java.util.concurrent.Executors

// OverlayTts — TTS Piper (VITS pt_BR-faber-medium) 100% offline para o overlay
// nativo (FloatingVoiceService, Kotlin puro), reproduzindo a MESMA voz do Home.
//
// O Home fala via pacote Flutter sherpa_onnx (Dart FFI, libsherpa-onnx-c-api.so).
// Aqui usamos o binding oficial Kotlin (Tts.kt, libsherpa-onnx-jni.so) — MESMA
// versao 1.13.4, MESMO modelo. O jni.so so amarra em libonnxruntime.so, que o
// plugin Flutter ja empacota no APK; por isso adicionamos apenas o jni.so a
// jniLibs (ver Etapa 1) e nao ha colisao de biblioteca nativa.
//
// sherpa le o modelo de CAMINHOS de arquivo (nao de assets): na 1a vez copiamos
// modelo + tokens + a arvore espeak-ng-data (exigida pelo Piper) do APK para
// filesDir. Copia propria do overlay, independente do Home (nao acopla caminho).
//
// Geracao (CPU-bound) roda em executor single-thread (serializa falas, nao
// bloqueia a main thread do overlay). Playback via AudioTrack float PCM.
object OverlayTts {
    // Prefixo do asset dentro do APK (Flutter empacota tudo sob flutter_assets/).
    private const val ASSET_ROOT = "flutter_assets/assets/models/piper_pt_br_faber"
    private const val MODEL_FILE = "pt_BR-faber-medium.onnx"
    private const val TOKENS_FILE = "tokens.txt"
    private const val ESPEAK_DIR = "espeak-ng-data"

    // Executor single-thread: sintetiza uma fala por vez, fora da main thread.
    private val exec = Executors.newSingleThreadExecutor()

    // Instancia nativa carregada uma vez (vive no processo). Reaproveitada.
    @Volatile private var tts: OfflineTts? = null

    // true quando o modelo ja carregou e speak() pode gerar imediatamente.
    val isReady: Boolean get() = tts != null

    // Carrega o modelo (idempotente, thread-safe). Retorna true se pronto.
    // Chamavel em background (prewarm no onCreate) para a 1a fala nao pagar a
    // copia dos assets + load do modelo em runtime.
    @Synchronized
    fun ensureReady(context: Context): Boolean {
        if (tts != null) return true
        return try {
            val root = File(context.filesDir, "sherpa_overlay/piper_pt_br_faber")
            val model = copyAsset(context, "$ASSET_ROOT/$MODEL_FILE", File(root, MODEL_FILE))
            val tokens = copyAsset(context, "$ASSET_ROOT/$TOKENS_FILE", File(root, TOKENS_FILE))
            val espeak = File(root, ESPEAK_DIR)
            copyAssetTree(context, "$ASSET_ROOT/$ESPEAK_DIR", espeak)

            // Piper = VITS; dataDir aponta para espeak-ng-data (fonemizacao).
            // Config identica a do Home (numThreads=2) para voz/latencia iguais.
            val cfg = OfflineTtsConfig(
                model = OfflineTtsModelConfig(
                    vits = OfflineTtsVitsModelConfig(
                        model = model.absolutePath,
                        tokens = tokens.absolutePath,
                        dataDir = espeak.absolutePath,
                    ),
                    numThreads = 2,
                    debug = false,
                )
            )
            tts = OfflineTts(config = cfg)
            true
        } catch (e: Throwable) {
            // Falha de load (modelo ausente/corrompido, ABI incompativel, etc.):
            // fica nulo, isReady=false, e o chamador cai no fallback TTS nativo.
            tts = null
            false
        }
    }

    // Sintetiza [text] e reproduz. Nao bloqueia o chamador: enfileira no executor.
    // [onResult] recebe true se falou, false se falhou (carga/geracao) — o
    // FloatingVoiceService usa false para acionar o fallback do TTS do sistema.
    fun speak(context: Context, text: String, onResult: (Boolean) -> Unit) {
        if (text.isBlank()) { onResult(true); return }
        exec.execute {
            try {
                if (!ensureReady(context)) { onResult(false); return@execute }
                val engine = tts ?: run { onResult(false); return@execute }
                // sid=0 (voz unica), speed=1.0 (natural) — iguais ao Home.
                val audio = engine.generate(text, sid = 0, speed = 1.0f)
                if (audio.samples.isEmpty()) { onResult(false); return@execute }
                playBlocking(audio.samples, audio.sampleRate)
                onResult(true)
            } catch (e: Throwable) {
                onResult(false)
            }
        }
    }

    // Reproduz samples float [-1,1] mono via AudioTrack (streaming). Bloqueia esta
    // thread do executor ate drenar o audio — serializa a proxima fala naturalmente.
    private fun playBlocking(samples: FloatArray, sampleRate: Int) {
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT
        )
        val at = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuf, 4096))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        try {
            at.play()
            // WRITE_BLOCKING: retorna quando todos os samples foram entregues ao track.
            at.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
            // Espera o playback drenar (head alcanca o total de frames escritos).
            while (at.playbackHeadPosition < samples.size && at.playState == AudioTrack.PLAYSTATE_PLAYING) {
                Thread.sleep(20)
            }
        } finally {
            try { at.stop() } catch (_: Throwable) {}
            at.release()
        }
    }

    // Copia um asset do APK para [dest] se ainda nao existir. Retorna o arquivo.
    private fun copyAsset(context: Context, assetPath: String, dest: File): File {
        if (dest.exists() && dest.length() > 0) return dest
        dest.parentFile?.mkdirs()
        context.assets.open(assetPath).use { input ->
            dest.outputStream().use { input.copyTo(it) }
        }
        return dest
    }

    // Copia recursivamente a arvore de assets sob [assetDir] para [destDir],
    // espelhando a hierarquia. AssetManager.list() retorna vazio para arquivos e
    // os nomes-filhos para diretorios (a arvore espeak nao tem pasta vazia).
    private fun copyAssetTree(context: Context, assetDir: String, destDir: File) {
        val children = context.assets.list(assetDir) ?: return
        destDir.mkdirs()
        for (name in children) {
            val childAsset = "$assetDir/$name"
            val sub = context.assets.list(childAsset)
            if (sub != null && sub.isNotEmpty()) {
                copyAssetTree(context, childAsset, File(destDir, name)) // subdiretorio
            } else {
                copyAsset(context, childAsset, File(destDir, name))     // arquivo
            }
        }
    }
}
