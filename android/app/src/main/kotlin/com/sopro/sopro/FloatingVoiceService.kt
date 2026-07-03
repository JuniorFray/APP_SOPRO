package com.sopro.sopro

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.*
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.util.Base64
import android.util.Log
import android.view.*
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID

// FloatingVoiceService — botão circular flutuante de voz sobre todos os apps.
//
// Grava áudio diretamente, envia ao Gemini via coroutine (IO thread) e escreve
// o trigger no banco SQLite — tudo sem abrir o app ou mudar o foco do usuário.
//
// Fluxo de uso:
//   1. SEGURAR (> 300 ms) → inicia gravação com beep de confirmação
//   2. SOLTAR             → Gemini processa; trigger criado no DB; TTS confirma
//   3. ARRASTAR           → reposiciona botão; posição persiste em SharedPreferences
//
// FIX 1: MediaRecorder liberado em TODOS os caminhos (catch + startRecording cleanup).
// FIX 2: errorStream lido com readBytes() — sem BufferedReader em nenhum caminho HTTP.
// FIX 3: speak() salva timestamp → Flutter skip TTS se floating falou há < 10 s.
// FIX 4: TTS seleciona melhor voz pt-BR offline; setSpeechRate(0.95) + setPitch(1.05).
// FIX 5: nomes genéricos (ambiente, local, lugar…) rejeitados → pede nome real.
//
// IPC com o app:
//   FloatingVoiceService escreve em "sopro_float_state" → KEY_PENDING_INTENT.
//   MainActivity.onResume() lê e invoca "processPendingIntent" no Flutter.
class FloatingVoiceService : Service(), TextToSpeech.OnInitListener {

    // Resultado do processamento Gemini — error não nulo indica falha
    data class FloatVoiceResult(
        val intent:         String?,
        val environment:    String?,
        val triggerTitle:   String?,
        val triggerContent: String?,
        val transcript:     String?,
        val error:          String? = null,
    )

    companion object {
        private const val TAG      = "FloatingVoiceService"
        const val EXTRA_OPEN_VOICE = "OPEN_VOICE"

        private const val NOTIF_ID   = 9001
        private const val CHANNEL_ID = "sopro_background"

        // SharedPreferences do Flutter — onde lemos a Gemini API key, device ID
        // e onde gravamos o timestamp do último speak() (FIX 3)
        private const val FLUTTER_PREFS       = "FlutterSharedPreferences"
        private const val KEY_GEMINI_API      = "flutter.gemini_api_key"
        private const val KEY_DEVICE_ID       = "flutter.logger_device_id"
        // Chave lida pelo Dart em VoiceService.speak() para evitar TTS duplicado
        private const val KEY_FLOATING_SPOKE  = "flutter.floating_spoke_at"

        // Posição salva do botão
        private const val PREF_FILE = "sopro_float_pos"
        private const val KEY_BTN_X = "btn_x"
        private const val KEY_BTN_Y = "btn_y"

        // IPC com o app: estado de voz e pedidos pendentes
        // Lido por MainActivity.onResume() para delegar ao Flutter
        internal const val FLOAT_STATE_PREFS  = "sopro_float_state"
        internal const val KEY_VOICE_STATE    = "voice_state"
        internal const val VAL_AWAITING_NAME  = "awaiting_env_name"
        internal const val KEY_PENDING_INTENT = "floating_pending_intent"
        internal const val KEY_PENDING_TS     = "floating_pending_timestamp"

        // Supabase — mesma URL/chave do AppLogger.dart (publishable key, INSERT-only RLS)
        private const val SUPABASE_URL =
            "https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs"
        private const val SUPABASE_KEY =
            "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"

        // Endpoint Gemini — mesmo modelo usado pelo Dart (AppConstants.geminiModel)
        private const val GEMINI_ENDPOINT =
            "https://generativelanguage.googleapis.com/v1beta/models/" +
            "gemini-2.5-flash:generateContent"

        // FIX 5: nomes genéricos que não identificam um lugar real
        // Se Gemini retornar um desses, tratamos como "sem nome" e pedimos novamente
        private val BLOCKED_ENV_NAMES = setOf(
            "ambiente", "local", "lugar", "aqui", "este", "esse",
            "novo", "meu", "um", "o", "a",
        )
    }

    // ── Views e WindowManager ─────────────────────────────────────────────────
    private var windowManager:   WindowManager?              = null
    private var containerView:   FrameLayout?                = null
    private var btnView:         ImageView?                  = null
    private var layoutParams:    WindowManager.LayoutParams? = null
    // 3 Views circulares para ondas ripple durante gravação
    private val rippleViews      = mutableListOf<View>()
    private val rippleAnimators  = mutableListOf<ValueAnimator>()

    // ── Estado de arraste / toque ─────────────────────────────────────────────
    // Posição e gravação são estados INDEPENDENTES — isDragging foi removido.
    private var dragStartX = 0f
    private var dragStartY = 0f
    private var initParamX = 0
    private var initParamY = 0
    private var pressStartTime: Long = 0L
    private var recordingStartRunnable: Runnable? = null

    // ── Gravação (MediaRecorder) ───────────────────────────────────────────────
    // FIX 1: mediaRecorder DEVE ser liberado em TODOS os caminhos de saída.
    // Usar releaseMediaRecorder() que garante stop → release → null.
    private var mediaRecorder: MediaRecorder? = null
    private var audioFile:     File?          = null
    private var isRecording                   = false

    // ── TTS nativo — fala resposta sem depender do app Flutter ────────────────
    // Inicializado assincronamente via onInit(); nullable para evitar crash antes do init.
    private var tts: TextToSpeech? = null

    // ── CoroutineScope para chamadas de rede em IO thread ─────────────────────
    // SupervisorJob: falha de uma coroutine não cancela as outras.
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── Handler principal (UI) ────────────────────────────────────────────────
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── ActivityLifecycleCallbacks — oculta botão quando Sopro está em foco ──
    private var soperoActivitiesVisible = 0
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) {
            soperoActivitiesVisible++
            mainHandler.post { containerView?.visibility = View.GONE }
        }
        override fun onActivityStopped(activity: Activity) {
            soperoActivitiesVisible--
            if (soperoActivitiesVisible <= 0) {
                mainHandler.postDelayed({ containerView?.visibility = View.VISIBLE }, 200)
            }
        }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityResumed(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Ciclo de vida do Service
    // ═════════════════════════════════════════════════════════════════════════

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "SYSTEM_ALERT_WINDOW não concedido — serviço encerrado")
            stopSelf(); return
        }
        // TTS nativo — onInit() é chamado assincronamente após init
        tts = TextToSpeech(this, this)
        startForeground(NOTIF_ID, buildSilentNotification())
        createOverlayButton()
        (applicationContext as Application).registerActivityLifecycleCallbacks(lifecycleCallbacks)
        Log.d(TAG, "FloatingVoiceService iniciado")
    }

    // FIX 4: seleciona melhor voz pt-BR offline e ajusta velocidade/tom após init assíncrono
    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.w(TAG, "TTS falhou ao inicializar (status=$status)")
            return
        }
        tts?.language = Locale("pt", "BR")

        // FIX 4a: filtra vozes pt-BR, offline, com qualidade >= NORMAL; ordena pela melhor
        val bestVoice = tts?.voices
            ?.filter { v ->
                v.locale.language == "pt" && v.locale.country == "BR"
                    && !v.isNetworkConnectionRequired
                    && v.quality >= Voice.QUALITY_NORMAL
            }
            ?.sortedByDescending { it.quality }
            ?.firstOrNull()

        if (bestVoice != null) {
            tts?.voice = bestVoice
            Log.d(TAG, "TTS — voz selecionada: ${bestVoice.name} (quality=${bestVoice.quality})")
        } else {
            Log.d(TAG, "TTS — usando voz padrão pt-BR")
        }

        // FIX 4b: velocidade levemente reduzida + tom ligeiramente mais alto = mais claro
        tts?.setSpeechRate(0.95f)
        tts?.setPitch(1.05f)
    }

    override fun onDestroy() {
        serviceScope.cancel()
        (applicationContext as Application).unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        // FIX 1: garante liberação do MediaRecorder ao encerrar o serviço
        releaseMediaRecorder()
        rippleAnimators.forEach { it.cancel() }
        mainHandler.removeCallbacksAndMessages(null)
        tts?.stop(); tts?.shutdown(); tts = null
        removeOverlayButton()
        Log.d(TAG, "FloatingVoiceService encerrado")
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Notificação foreground mínima (IMPORTANCE_MIN — sem som/ícone na barra)
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildSilentNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Sopro — Segundo plano",
                        NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false) }
                )
            }
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Sopro")
            .setContentText("Botão de voz ativo")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Criação da janela overlay
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun createOverlayButton() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val btnPx       = dpToPx(56)  // botão principal 56 dp
        val ripplePx    = dpToPx(60)  // cada ripple parte de 60dp (escala até 2.5 = 150dp)
        val containerPx = dpToPx(160) // container acomoda ripples animados

        val container = FrameLayout(this)
        containerView = container

        // 3 Views de ripple atrás do botão, visíveis apenas durante gravação
        repeat(3) {
            val ripple = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0xFFE8445A.toInt()) // accent — fica transparente via alpha
                }
                alpha = 0f // oculto até gravação iniciar
            }
            rippleViews.add(ripple)
            container.addView(ripple, FrameLayout.LayoutParams(ripplePx, ripplePx).apply {
                gravity = Gravity.CENTER
            })
        }

        // Botão circular com ícone do app — fica sobre os ripples
        val btn = ImageView(this).apply {
            setImageResource(R.drawable.ic_launcher_foreground)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10))
            background = circleDrawable(0xFFE8445A.toInt())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dpToPx(6).toFloat()
            }
        }
        btnView = btn
        container.addView(btn, FrameLayout.LayoutParams(btnPx, btnPx).apply {
            gravity = Gravity.CENTER
        })

        val (defX, defY) = defaultButtonPosition(containerPx)
        val pos    = getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val savedX = pos.getInt(KEY_BTN_X, defX)
        val savedY = pos.getInt(KEY_BTN_Y, defY)

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            containerPx, containerPx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            // TOP|START: x/y são offsets absolutos do canto superior esquerdo.
            // Permite movimento livre horizontal E vertical sem inversão de eixo.
            gravity = Gravity.TOP or Gravity.START
            x = savedX; y = savedY
        }
        layoutParams = params

        container.setOnTouchListener { _, event -> handleTouch(event); true }
        windowManager?.addView(container, params)
    }

    private fun circleDrawable(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL; setColor(color)
    }

    private fun removeOverlayButton() {
        containerView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        containerView = null; windowManager = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tratamento de toque — SEGURAR para gravar, SOLTAR para processar, ARRASTAR para mover
    //
    // Gravação e posição são estados INDEPENDENTES:
    //   - ACTION_MOVE SEMPRE reposiciona o botão, NUNCA cancela gravação em andamento.
    //   - ACTION_UP SEMPRE processa o áudio se estiver gravando, mesmo que tenha arrastado.
    //   - Apenas ACTION_CANCEL descarta a gravação (evento de sistema).
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragStartX     = event.rawX
                dragStartY     = event.rawY
                initParamX     = layoutParams?.x ?: 0
                initParamY     = layoutParams?.y ?: 0
                pressStartTime = System.currentTimeMillis()

                // Agenda gravação após 300 ms de hold — cancelado em ACTION_UP se soltar antes
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                val run = Runnable { startRecording() }
                recordingStartRunnable = run
                mainHandler.postDelayed(run, 300L)
            }

            MotionEvent.ACTION_MOVE -> {
                // SEMPRE reposiciona o botão, NUNCA interfere com gravação em andamento
                val dx = (event.rawX - dragStartX).toInt()
                val dy = (event.rawY - dragStartY).toInt()
                layoutParams?.let { p ->
                    p.x = initParamX + dx
                    p.y = initParamY + dy
                    try { windowManager?.updateViewLayout(containerView, p) }
                    catch (_: Exception) {}
                }
            }

            MotionEvent.ACTION_UP -> {
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null

                // Salva posição final — sempre, independente de ter gravado
                layoutParams?.let { p ->
                    getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                        .edit().putInt(KEY_BTN_X, p.x).putInt(KEY_BTN_Y, p.y).apply()
                }

                val duration = System.currentTimeMillis() - pressStartTime
                when {
                    isRecording     -> stopAndProcess()
                    duration < 300L -> showToast("Segure para gravar")
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                // Evento de sistema — descarta gravação em andamento
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null
                if (isRecording) {
                    isRecording = false
                    releaseMediaRecorder()
                    revertButtonAppearance()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gravação de áudio (MediaRecorder)
    // ─────────────────────────────────────────────────────────────────────────

    private fun startRecording() {
        if (isRecording) return

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            showToast("Permissão de microfone necessária")
            Log.w(TAG, "RECORD_AUDIO não concedido — gravação cancelada")
            return
        }

        // FIX 1: libera instância anterior antes de criar nova (evita resource leak)
        releaseMediaRecorder()

        // Filename com timestamp evita corrupção em gravações simultâneas
        audioFile = File(cacheDir, "floating_voice_${System.currentTimeMillis()}.m4a").also {
            if (it.exists()) it.delete()
        }

        try {
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()
            mediaRecorder = recorder

            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(8000)     // 8 kHz — qualidade de voz
                setAudioEncodingBitRate(12000) // 12 kbps — arquivo minúsculo (~1 KB/s)
                setOutputFile(audioFile!!.absolutePath)
                prepare()
                start()
            }
            isRecording = true

            // Beep curto (120 ms) confirma ativação do microfone ao usuário
            try {
                val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
                toneGen.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                mainHandler.postDelayed({ toneGen.release() }, 200L)
            } catch (e: Exception) {
                Log.w(TAG, "ToneGenerator indisponível: ${e.message}")
            }

            animateButtonScale(from = 1.0f, to = 1.3f)
            btnView?.background = circleDrawable(0xFFFF2244.toInt())
            startRippleAnimations()

            mainHandler.postDelayed({ stopAndProcess() }, 10_000L)
            Log.d(TAG, "Gravação iniciada: ${audioFile!!.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao iniciar MediaRecorder: ${e.message}")
            showToast("Erro ao acessar microfone")
            isRecording = false
            // FIX 1: libera mesmo em caso de falha no prepare()/start()
            releaseMediaRecorder()
        }
    }

    private fun stopAndProcess() {
        if (!isRecording) return
        mainHandler.removeCallbacksAndMessages(null)

        // FIX 1: usa releaseMediaRecorder() que garante stop → release → null
        isRecording = false
        releaseMediaRecorder()
        revertButtonAppearance()

        val file = audioFile
        if (file == null || !file.exists() || file.length() == 0L) {
            showToast("Áudio vazio — tente novamente"); return
        }

        Log.d(TAG, "Áudio: ${file.length()} bytes — enviando ao Gemini (IO thread)")

        serviceScope.launch {
            logToSupabase("floating_voice_debug", mapOf(
                "step" to "before_gemini",
                "audio_bytes" to file.length().toString(),
            ))

            val result = callGeminiWithAudio(file)

            logToSupabase("floating_voice_debug", mapOf(
                "step" to "after_gemini",
                "intent" to (result.intent ?: "null"),
                "error" to (result.error ?: "null"),
            ))

            withContext(Dispatchers.Main) { executeVoiceResult(result) }
        }
    }

    // FIX 1: método centralizado de liberação — stop → release → null.
    // Chamado de TODOS os caminhos: sucesso, erro, cancel e onDestroy.
    // try/catch separados garantem que o release sempre acontece mesmo se stop falhar.
    private fun releaseMediaRecorder() {
        try { mediaRecorder?.stop() }  catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
    }

    // Restaura aparência do botão ao estado idle (sem gravação)
    private fun revertButtonAppearance() {
        stopRippleAnimations()
        animateButtonScale(from = btnView?.scaleX ?: 1.3f, to = 1.0f, durationMs = 150L)
        btnView?.background = circleDrawable(0xFFE8445A.toInt())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gemini Audio API — chamado exclusivamente de Dispatchers.IO
    // ─────────────────────────────────────────────────────────────────────────

    private fun callGeminiWithAudio(file: File): FloatVoiceResult {
        val apiKey = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GEMINI_API, "") ?: ""

        if (apiKey.isEmpty()) {
            Log.w(TAG, "Gemini API key ausente")
            return FloatVoiceResult(null, null, null, null, null, error = "no_api_key")
        }

        val audioBase64 = Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)

        // Lê ambientes diretamente do SQLite — garante nomes exatos do banco no prompt
        val envNames = readEnvironmentNamesFromDb()
        val envCtx = if (envNames.isNotEmpty())
            "\nAmbientes existentes: ${envNames.joinToString(", ")}." else ""

        val prompt = """
Extraia a intenção do áudio em JSON. Responda APENAS com JSON, sem markdown.
Schemas:
  create_trigger:     {"intent":"create_trigger","transcricao":"","environment":"nome_exato","trigger":{"title":"acao_infinitivo","content":""}}
  create_environment: {"intent":"create_environment","transcricao":"","environment":{"name":"nome_do_local"}}
  unknown:            {"intent":"unknown","transcricao":"texto"}

REGRA trigger.title: apenas a ação, infinitivo, max 50 chars, sem pronomes.$envCtx
""".trimIndent()

        val body = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("parts", JSONArray().apply {
                        put(JSONObject().put("text", prompt))
                        put(JSONObject().apply {
                            put("inline_data", JSONObject().apply {
                                put("mime_type", "audio/m4a")
                                put("data", audioBase64)
                            })
                        })
                    })
                })
            })
            put("generationConfig", JSONObject().apply {
                put("temperature", 0); put("maxOutputTokens", 256)
            })
        }.toString()

        return try {
            val url  = URL("$GEMINI_ENDPOINT?key=$apiKey")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 30_000; readTimeout = 30_000; doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }

            val code = conn.responseCode
            if (code != 200) {
                // FIX 2: errorStream lido com readBytes() — sem BufferedReader em nenhum caminho
                val errBody = conn.errorStream?.readBytes()?.toString(Charsets.UTF_8) ?: ""
                Log.d(TAG, "Gemini HTTP $code: $errBody")
                conn.disconnect()
                return FloatVoiceResult(null, null, null, null, null, error = "http_$code")
            }

            // Lê TODOS os bytes via loop explícito — evita truncamento em payloads grandes
            val responseStream = conn.inputStream
            val responseBytes  = ByteArrayOutputStream()
            val buffer         = ByteArray(4096)
            var bytesRead: Int
            while (responseStream.read(buffer).also { bytesRead = it } != -1) {
                responseBytes.write(buffer, 0, bytesRead)
            }
            responseStream.close()
            conn.disconnect()
            val raw = responseBytes.toString("UTF-8")

            parseGeminiResponse(raw)
        } catch (e: Exception) {
            Log.e(TAG, "Gemini request error: $e")
            FloatVoiceResult(null, null, null, null, null, error = e.message)
        }
    }

    private fun parseGeminiResponse(raw: String): FloatVoiceResult {
        return try {
            val text = JSONObject(raw)
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts").getJSONObject(0)
                .getString("text")
                .replace(Regex("```[a-zA-Z]*\\n?"), "").replace("```", "").trim()

            val parsed     = JSONObject(text)
            val intent     = parsed.optString("intent", "unknown")
            val transcript = parsed.optString("transcricao", "")

            when (intent) {
                "create_trigger" -> {
                    val trigger = parsed.optJSONObject("trigger")
                    FloatVoiceResult(
                        intent         = intent,
                        environment    = parsed.optString("environment").takeIf { it.isNotEmpty() },
                        triggerTitle   = trigger?.optString("title")?.takeIf { it.isNotEmpty() },
                        triggerContent = trigger?.optString("content")?.takeIf { it.isNotEmpty() },
                        transcript     = transcript,
                    )
                }
                "create_environment" -> {
                    val env  = parsed.optJSONObject("environment")
                    val name = env?.optString("name")?.takeIf { it.isNotEmpty() }
                        ?: parsed.optString("environment").takeIf { it.isNotEmpty() }
                    FloatVoiceResult(
                        intent         = intent,
                        environment    = name,
                        triggerTitle   = null, triggerContent = null,
                        transcript     = transcript,
                    )
                }
                else -> FloatVoiceResult(
                    intent         = "unknown",
                    environment    = null,
                    triggerTitle   = null, triggerContent = null,
                    transcript     = transcript,
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao parsear Gemini: $e")
            FloatVoiceResult(null, null, null, null, null, error = "parse_error: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execução do resultado — sempre na Main thread (via withContext(Main))
    // ─────────────────────────────────────────────────────────────────────────

    private fun executeVoiceResult(result: FloatVoiceResult) {
        if (result.error != null) {
            showToast("Erro: ${result.error.take(60)}")
            speak("Não entendi. Pressione novamente para tentar.")
            return
        }

        val statePrefs = getSharedPreferences(FLOAT_STATE_PREFS, Context.MODE_PRIVATE)
        val voiceState = statePrefs.getString(KEY_VOICE_STATE, null)

        // Se estava aguardando nome de ambiente, usa transcript como nome.
        // NÃO reenvia ao Gemini — usa diretamente o texto gravado.
        if (voiceState == VAL_AWAITING_NAME) {
            statePrefs.edit().remove(KEY_VOICE_STATE).apply()
            val rawName  = result.transcript?.trim() ?: ""
            // FIX 5: rejeita nomes genéricos mesmo no fluxo de "aguardando nome"
            val envName  = rawName.takeIf { it.isNotEmpty() && !BLOCKED_ENV_NAMES.contains(it.lowercase()) } ?: ""
            if (envName.isNotEmpty()) {
                savePendingIntent(JSONObject().apply {
                    put("intent", "create_environment"); put("name", envName)
                }.toString())
                showToast("'$envName' anotado! Abra o Sopro para confirmar o local.")
                speak("Pronto! Abra o Sopro para confirmar o local de $envName.")
            } else {
                // Nome ainda genérico ou vazio — pede novamente (loop de até 1 tentativa)
                statePrefs.edit().putString(KEY_VOICE_STATE, VAL_AWAITING_NAME).apply()
                showToast("Esse não parece um nome de lugar. Tente um nome mais específico.")
                speak("Qual é o nome do lugar? Por exemplo: casa, trabalho ou academia.")
                mainHandler.postDelayed({ showToast("Segure o botão para gravar o nome.") }, 2500L)
            }
            return
        }

        when (result.intent) {
            "create_trigger" -> {
                val envName = result.environment ?: ""
                val title   = result.triggerTitle  ?: ""
                if (envName.isNotEmpty() && title.isNotEmpty()) {
                    createTriggerInDb(envName, title, result.triggerContent ?: "")
                } else {
                    showToast("Diga: 'lembra de X quando chegar em Y'")
                    speak("Não entendi. Diga: lembra de X quando chegar em Y.")
                }
            }
            "create_environment" -> {
                val rawName = result.environment ?: ""
                // FIX 5: rejeita nomes genéricos (ambiente, local, aqui…) tratando-os como null
                val envName = rawName.takeIf {
                    it.isNotEmpty() && !BLOCKED_ENV_NAMES.contains(it.lowercase().trim())
                } ?: ""

                if (envName.isEmpty()) {
                    // Sem nome válido — salva estado e pede via TTS
                    statePrefs.edit().putString(KEY_VOICE_STATE, VAL_AWAITING_NAME).apply()
                    showToast("Qual é o nome do ambiente?")
                    speak("Qual é o nome do ambiente?")
                    // Delay de 2000 ms antes de pedir a gravação — evita que o mic
                    // capture este áudio TTS como entrada da próxima gravação
                    mainHandler.postDelayed({
                        showToast("Segure o botão para gravar o nome.")
                    }, 2000L)
                } else {
                    // Precisa de GPS → delega ao app via IPC (MainActivity.onResume)
                    savePendingIntent(JSONObject().apply {
                        put("intent", "create_environment"); put("name", envName)
                    }.toString())
                    showToast("'$envName' anotado! Abra o Sopro para confirmar o local.")
                    speak("Pronto! Ambiente $envName criado.")
                }
            }
            else -> {
                showToast("Não entendi. Abra o Sopro para comandos avançados.")
                speak("Não entendi. Pressione novamente para tentar.")
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Escrita direta no banco SQLite (sem Flutter Engine)
    // ─────────────────────────────────────────────────────────────────────────

    private fun createTriggerInDb(envName: String, title: String, content: String) {
        val dbFile = findDbFile() ?: run {
            showToast("Abra o Sopro pelo menos uma vez"); return
        }

        try {
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                .use { db ->
                    val envId = db.rawQuery(
                        "SELECT id FROM environments WHERE LOWER(name) = LOWER(?)",
                        arrayOf(envName)
                    ).use { c -> if (c.moveToFirst()) c.getString(0) else null }

                    if (envId == null) {
                        showToast("Local '$envName' não encontrado no Sopro")
                        speak("Não encontrei o local $envName.")
                        return
                    }

                    db.execSQL(
                        "INSERT INTO triggers (id, environment_id, title, content, is_active, created_at)" +
                        " VALUES (?, ?, ?, ?, 1, ?)",
                        arrayOf(UUID.randomUUID().toString(), envId, title, content,
                                System.currentTimeMillis())
                    )
                    showToast("Anotado! Vou te lembrar de $title em $envName ✓")
                    speak("Anotado! Vou te lembrar de $title quando chegar em $envName.")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao criar trigger: $e")
            showToast("Erro ao salvar lembrete")
        }
    }

    // Lê nomes de ambientes direto do SQLite — garante nomes exatos no prompt Gemini.
    // Chamado de Dispatchers.IO, portanto acesso ao DB é seguro.
    private fun readEnvironmentNamesFromDb(): List<String> {
        val dbFile = findDbFile() ?: return emptyList()
        return try {
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                .use { db ->
                    db.rawQuery("SELECT name FROM environments WHERE deleted_at IS NULL", null)
                        .use { cursor ->
                            val names = mutableListOf<String>()
                            while (cursor.moveToNext()) names.add(cursor.getString(0))
                            names
                        }
                }
        } catch (_: Exception) {
            // Tabela pode não ter deleted_at — tenta sem WHERE
            try {
                SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                    .use { db ->
                        db.rawQuery("SELECT name FROM environments", null).use { cursor ->
                            val names = mutableListOf<String>()
                            while (cursor.moveToNext()) names.add(cursor.getString(0))
                            names
                        }
                    }
            } catch (e2: Exception) {
                Log.w(TAG, "readEnvironmentNamesFromDb falhou: ${e2.message}")
                emptyList()
            }
        }
    }

    // Localiza sopro.db entre os caminhos possíveis (mesmo padrão do BootReceiver)
    private fun findDbFile(): File? {
        val candidates = listOf(
            File(filesDir.parentFile, "app_flutter/sopro.db"),
            File(filesDir, "sopro.db"),
            getDatabasePath("sopro.db"),
        )
        return candidates.firstOrNull { it.exists() }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Efeito visual ao pressionar
    // ─────────────────────────────────────────────────────────────────────────

    private fun animateButtonScale(from: Float, to: Float, durationMs: Long = 200L) {
        val btn = btnView ?: return
        ObjectAnimator.ofFloat(btn, "scaleX", from, to).apply {
            duration = durationMs; interpolator = OvershootInterpolator(); start()
        }
        ObjectAnimator.ofFloat(btn, "scaleY", from, to).apply {
            duration = durationMs; interpolator = OvershootInterpolator(); start()
        }
    }

    // 3 ondas ripple com delay de 300 ms entre si.
    // Cada onda: scale 1.0→2.5, alpha 0.6→0.0 em 900 ms, em loop infinito.
    private fun startRippleAnimations() {
        rippleAnimators.forEach { it.cancel() }
        rippleAnimators.clear()
        rippleViews.forEachIndexed { i, view ->
            val anim = ValueAnimator.ofFloat(0f, 1f).apply {
                duration    = 900L
                startDelay  = (i * 300L)
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener { va ->
                    val p = va.animatedValue as Float
                    view.scaleX = 1f + 1.5f * p
                    view.scaleY = 1f + 1.5f * p
                    view.alpha  = 0.6f * (1f - p)
                }
            }
            rippleAnimators.add(anim)
            anim.start()
        }
    }

    private fun stopRippleAnimations() {
        rippleAnimators.forEach { it.cancel() }
        rippleAnimators.clear()
        rippleViews.forEach { v -> v.scaleX = 1f; v.scaleY = 1f; v.alpha = 0f }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Supabase logging — fire-and-forget, chamado de Dispatchers.IO
    // ─────────────────────────────────────────────────────────────────────────

    private fun logToSupabase(eventType: String, payload: Map<String, String>) {
        val deviceId = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_ID, "native_service") ?: "native_service"

        val body = JSONObject().apply {
            put("device_id",  deviceId)
            put("event_type", eventType)
            put("payload",    JSONObject(payload as Map<*, *>))
        }.toString()

        try {
            val url  = URL(SUPABASE_URL)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5_000; readTimeout = 5_000; doOutput = true
                setRequestProperty("Content-Type",  "application/json")
                setRequestProperty("apikey",        SUPABASE_KEY)
                setRequestProperty("Authorization", "Bearer $SUPABASE_KEY")
                setRequestProperty("Prefer",        "return=minimal")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }
            conn.inputStream.close()
            conn.disconnect()
        } catch (e: Exception) {
            Log.d(TAG, "logToSupabase falhou (ignorado): ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IPC — salva pedido pendente para o app processar no próximo onResume()
    // ─────────────────────────────────────────────────────────────────────────

    private fun savePendingIntent(json: String) {
        getSharedPreferences(FLOAT_STATE_PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_PENDING_INTENT, json)
            .putLong(KEY_PENDING_TS, System.currentTimeMillis())
            .apply()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utilitários
    // ─────────────────────────────────────────────────────────────────────────

    private fun showToast(msg: String) =
        mainHandler.post { Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show() }

    // FIX 3: fala texto e salva timestamp em FlutterSharedPreferences.
    // O Dart lê "floating_spoke_at" em VoiceService.speak() para evitar TTS duplicado
    // se o app abrir dentro de 10 s após o botão flutuante ter falado.
    private fun speak(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "sopro_utt")
        // Grava timestamp para que o Flutter saiba que o serviço acabou de falar
        getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_FLOATING_SPOKE, System.currentTimeMillis()).apply()
    }

    private fun defaultButtonPosition(containerPx: Int): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val x  = (dm.widthPixels  - containerPx - dpToPx(24)).coerceAtLeast(0)
        val y  = (dm.heightPixels - containerPx - dpToPx(96)).coerceAtLeast(0)
        return Pair(x, y)
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()
}
