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
import android.media.ToneGenerator
import android.os.*
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
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
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Tasks
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

// FloatingVoiceService — botão circular flutuante de voz sobre todos os apps.
//
// Fluxo: SEGURAR (> 300 ms) → SpeechRecognizer escuta → SOLTAR → Gemini texto
// classifica → trigger criado no SQLite ou ambiente delegado via IPC.
//
// Etapa12: substituiu MediaRecorder + Gemini Audio por SpeechRecognizer + Gemini Texto.
//   - Sem arquivo de áudio, sem base64, sem chamada multipart.
//   - Transcript do STT enviado diretamente ao Gemini como texto.
//   - Confirmação de 5 s para criar_ambiente: aguardar = confirmar, pressionar = cancelar.
//
// FIX (mantidos das etapas anteriores):
//   FIX 3: speak() salva timestamp → Flutter skip TTS se floating falou há < 10 s.
//   FIX 4: TTS seleciona melhor voz pt-BR offline; setSpeechRate(0.95) + setPitch(1.05).
//   FIX 5: nomes genéricos (ambiente, local, lugar…) rejeitados → pede nome real.
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
        private const val FLUTTER_PREFS      = "FlutterSharedPreferences"
        private const val KEY_GEMINI_API     = "flutter.gemini_api_key"
        private const val KEY_DEVICE_ID      = "flutter.logger_device_id"
        // Chave lida pelo Dart em VoiceService.speak() para evitar TTS duplicado
        private const val KEY_FLOATING_SPOKE = "flutter.floating_spoke_at"

        // Posição salva do botão
        private const val PREF_FILE = "sopro_float_pos"
        private const val KEY_BTN_X = "btn_x"
        private const val KEY_BTN_Y = "btn_y"

        // Estado de voz: aguardando nome de ambiente (VAL_AWAITING_NAME)
        internal const val FLOAT_STATE_PREFS = "sopro_float_state"
        internal const val KEY_VOICE_STATE   = "voice_state"
        internal const val VAL_AWAITING_NAME = "awaiting_env_name"

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
    private var windowManager:  WindowManager?              = null
    private var containerView:  FrameLayout?                = null
    private var btnView:        ImageView?                  = null
    private var layoutParams:   WindowManager.LayoutParams? = null
    // 3 Views circulares para ondas ripple durante escuta
    private val rippleViews     = mutableListOf<View>()
    private val rippleAnimators = mutableListOf<ValueAnimator>()

    // ── Estado de arraste / toque ─────────────────────────────────────────────
    // Posição e escuta são estados INDEPENDENTES — arrastar nunca cancela escuta.
    private var dragStartX = 0f
    private var dragStartY = 0f
    private var initParamX = 0
    private var initParamY = 0
    private var pressStartTime: Long = 0L
    private var recordingStartRunnable: Runnable? = null

    // ── SpeechRecognizer — substitui MediaRecorder (Etapa12) ─────────────────
    // Criado na main thread em onCreate(); destruído na main thread em onDestroy().
    // isListening controla o estado de escuta (substitui isRecording).
    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening = false

    // ── TTS nativo — fala resposta sem depender do app Flutter ────────────────
    private var tts: TextToSpeech? = null

    // ── CoroutineScope para chamadas Gemini em IO thread ─────────────────────
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

        // SpeechRecognizer deve ser criado na main thread — onCreate() já é main
        initSpeechRecognizer()

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
        // SpeechRecognizer.destroy() deve ser chamado na main thread
        speechRecognizer?.destroy()
        speechRecognizer = null
        rippleAnimators.forEach { it.cancel() }
        mainHandler.removeCallbacksAndMessages(null)
        tts?.stop(); tts?.shutdown(); tts = null
        removeOverlayButton()
        Log.d(TAG, "FloatingVoiceService encerrado")
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SpeechRecognizer — criação e listener
    // ─────────────────────────────────────────────────────────────────────────

    private fun initSpeechRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "SpeechRecognizer não disponível neste dispositivo")
            return
        }
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {

            // Reconhecedor pronto — inicia animação de escuta
            override fun onReadyForSpeech(params: Bundle?) {
                startRippleAnimations()
            }

            // Usuário começou a falar
            override fun onBeginningOfSpeech() {}

            // Usuário parou de falar — muda visual para "processando"
            override fun onEndOfSpeech() {
                showProcessingState()
            }

            // Resultado final — classifica via Gemini ou usa diretamente como nome
            override fun onResults(results: Bundle?) {
                isListening = false
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (text.isNullOrBlank()) {
                    revertButtonAppearance()
                    speak("Não ouvi nada. Segure e tente novamente.")
                    return
                }

                Log.d(TAG, "STT resultado: $text")

                // Se estava aguardando nome de ambiente, usa transcript diretamente
                // (sem Gemini) — evita chamada de rede desnecessária e latência
                val statePrefs = getSharedPreferences(FLOAT_STATE_PREFS, Context.MODE_PRIVATE)
                if (statePrefs.getString(KEY_VOICE_STATE, null) == VAL_AWAITING_NAME) {
                    val syntheticResult = FloatVoiceResult(
                        intent         = "create_environment",
                        environment    = null, // tratado via transcript em executeVoiceResult
                        triggerTitle   = null,
                        triggerContent = null,
                        transcript     = text,
                    )
                    revertButtonAppearance()
                    executeVoiceResult(syntheticResult)
                    return
                }

                // Caso geral — envia ao Gemini para classificação em IO thread
                serviceScope.launch { processTextWithGemini(text) }
            }

            // Erro de reconhecimento — exibe mensagem amigável
            override fun onError(error: Int) {
                isListening = false
                val msg = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH         -> "Não entendi. Tente novamente."
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT   -> "Nenhuma fala detectada."
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT  -> "Sem conexão com a internet."
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Permissão de microfone negada."
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY  -> "Reconhecedor ocupado. Tente novamente."
                    else                                    -> "Erro ao reconhecer voz (código $error)."
                }
                Log.w(TAG, "SpeechRecognizer error=$error: $msg")
                revertButtonAppearance()
                speak(msg)
            }

            // Callbacks de sinal — não utilizados
            override fun onRmsChanged(rmsdB: Float)           {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onPartialResults(partial: Bundle?)   {}
            override fun onEvent(type: Int, params: Bundle?)  {}
        })
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

        // 3 Views de ripple atrás do botão, visíveis apenas durante escuta
        repeat(3) {
            val ripple = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0xFFE8445A.toInt()) // accent — fica transparente via alpha
                }
                alpha = 0f // oculto até escuta iniciar
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
    // Tratamento de toque — SEGURAR para escutar, SOLTAR para processar, ARRASTAR para mover
    //
    // Escuta e posição são estados INDEPENDENTES:
    //   - ACTION_MOVE SEMPRE reposiciona o botão, NUNCA cancela escuta em andamento.
    //   - ACTION_UP processa escuta se isListening, ou cancela env pendente se tap curto.
    //   - Apenas ACTION_CANCEL (evento de sistema) descarta escuta sem processar.
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragStartX     = event.rawX
                dragStartY     = event.rawY
                initParamX     = layoutParams?.x ?: 0
                initParamY     = layoutParams?.y ?: 0
                pressStartTime = System.currentTimeMillis()

                // Agenda escuta após 300 ms de hold — cancelado em ACTION_UP se soltar antes
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                val run = Runnable { startListeningForVoice() }
                recordingStartRunnable = run
                mainHandler.postDelayed(run, 1000L)
            }

            MotionEvent.ACTION_MOVE -> {
                // SEMPRE reposiciona o botão, NUNCA interfere com escuta em andamento
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

                // Salva posição final — sempre, independente de ter escutado
                layoutParams?.let { p ->
                    getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                        .edit().putInt(KEY_BTN_X, p.x).putInt(KEY_BTN_Y, p.y).apply()
                }

                val duration = System.currentTimeMillis() - pressStartTime
                when {
                    // Estava escutando → encerra escuta e aguarda onResults
                    isListening     -> stopListeningAndProcess()
                    // Tap curto sem contexto → dica de uso
                    duration < 300L -> showToast("Segure para gravar")
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                // Evento de sistema — descarta escuta sem processar
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null
                if (isListening) {
                    isListening = false
                    speechRecognizer?.cancel()
                    revertButtonAppearance()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Escuta por voz (SpeechRecognizer)
    // ─────────────────────────────────────────────────────────────────────────

    private fun startListeningForVoice() {
        if (isListening) return

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            showToast("Permissão de microfone necessária")
            Log.w(TAG, "RECORD_AUDIO não concedido — escuta cancelada")
            return
        }

        if (speechRecognizer == null) {
            showToast("Reconhecedor de voz não disponível")
            return
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
        }

        try {
            speechRecognizer?.startListening(intent)
            isListening = true

            // Beep curto (120 ms) confirma ativação do microfone ao usuário
            try {
                val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 30)
                toneGen.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                mainHandler.postDelayed({ toneGen.release() }, 200L)
            } catch (e: Exception) {
                Log.w(TAG, "ToneGenerator indisponível: ${e.message}")
            }

            animateButtonScale(from = 1.0f, to = 1.3f)
            btnView?.background = circleDrawable(0xFFFF2244.toInt())
            Log.d(TAG, "SpeechRecognizer: escuta iniciada")
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao iniciar SpeechRecognizer: ${e.message}")
            showToast("Erro ao acessar microfone")
            isListening = false
            revertButtonAppearance()
        }
    }

    // Encerra a captura — onEndOfSpeech → onResults ou onError disparam automaticamente
    private fun stopListeningAndProcess() {
        if (!isListening) return
        speechRecognizer?.stopListening()
        // isListening será false quando onResults ou onError disparar
        Log.d(TAG, "SpeechRecognizer: stopListening chamado")
    }

    // Estado visual "processando" — acionado em onEndOfSpeech (entre escuta e resultado)
    private fun showProcessingState() {
        stopRippleAnimations()
        animateButtonScale(from = btnView?.scaleX ?: 1.3f, to = 1.0f, durationMs = 150L)
        btnView?.background = circleDrawable(0xFF888888.toInt()) // cinza = aguardando Gemini
    }

    // Restaura aparência do botão ao estado idle (sem escuta, sem processamento)
    private fun revertButtonAppearance() {
        stopRippleAnimations()
        animateButtonScale(from = btnView?.scaleX ?: 1.3f, to = 1.0f, durationMs = 150L)
        btnView?.background = circleDrawable(0xFFE8445A.toInt())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gemini Texto — chamado exclusivamente de Dispatchers.IO (serviceScope)
    // ─────────────────────────────────────────────────────────────────────────

    private suspend fun processTextWithGemini(transcript: String) {
        logToSupabase("floating_voice_debug", mapOf(
            "step" to "stt_result", "transcript" to transcript
        ))

        val apiKey = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GEMINI_API, "") ?: ""

        if (apiKey.isEmpty()) {
            Log.w(TAG, "Gemini API key ausente")
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                speak("Chave da API não configurada. Abra o Sopro uma vez.")
            }
            return
        }

        // Lê ambientes direto do SQLite — garante nomes exatos do banco no prompt
        val envNames = readEnvironmentNamesFromDb()
        val envCtx   = if (envNames.isNotEmpty())
            "\nAmbientes existentes: ${envNames.joinToString(", ")}." else ""

        val prompt = """
Classifique o texto do usuário em JSON. Responda APENAS com JSON, sem markdown.
Schemas:
  create_trigger:     {"intent":"create_trigger","environment":"nome_exato","trigger":{"title":"acao_infinitivo","content":""}}
  create_environment: {"intent":"create_environment","environment":{"name":"nome_do_local"}}
  unknown:            {"intent":"unknown","transcricao":"texto_original"}

REGRA trigger.title: apenas a ação, infinitivo, máx 50 chars, sem pronomes.
IMPORTANTE: use nomes de ambiente EXATAMENTE como estão na lista abaixo.$envCtx

Texto: $transcript
""".trimIndent()

        val body = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("parts", JSONArray().apply {
                        put(JSONObject().put("text", prompt))
                    })
                })
            })
            put("generationConfig", JSONObject().apply {
                put("temperature", 0); put("maxOutputTokens", 256)
            })
        }.toString()

        val result = try {
            val url  = URL("$GEMINI_ENDPOINT?key=$apiKey")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000; readTimeout = 15_000; doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }

            val code = conn.responseCode
            // readBytes() garante leitura completa — sem truncamento em respostas grandes
            val responseBody = if (code == 200) {
                conn.inputStream.readBytes().toString(Charsets.UTF_8)
            } else {
                conn.errorStream?.readBytes()?.toString(Charsets.UTF_8) ?: ""
            }
            conn.disconnect()

            logToSupabase("floating_voice_debug", mapOf(
                "step"            to "after_gemini",
                "http"            to code.toString(),
                "response_length" to responseBody.length.toString(),
                "transcript"      to transcript,
            ))

            if (code != 200) {
                Log.d(TAG, "Gemini HTTP $code: ${responseBody.take(200)}")
                FloatVoiceResult(null, null, null, null, transcript, error = "http_$code")
            } else {
                parseGeminiResponse(responseBody, transcript)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Gemini request error: $e")
            FloatVoiceResult(null, null, null, null, transcript, error = e.message)
        }

        withContext(Dispatchers.Main) {
            revertButtonAppearance()
            executeVoiceResult(result)
        }
    }

    private fun parseGeminiResponse(raw: String, transcript: String): FloatVoiceResult {
        return try {
            val text = JSONObject(raw)
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts").getJSONObject(0)
                .getString("text")
                .replace(Regex("```[a-zA-Z]*\\n?"), "").replace("```", "").trim()

            val parsed = JSONObject(text)
            val intent = parsed.optString("intent", "unknown")

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
            FloatVoiceResult(null, null, null, null, transcript, error = "parse_error: ${e.message}")
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
        // NÃO reenvia ao Gemini — transcript vem direto do SpeechRecognizer (onResults).
        if (voiceState == VAL_AWAITING_NAME) {
            statePrefs.edit().remove(KEY_VOICE_STATE).apply()
            val rawName = result.transcript?.trim() ?: ""
            // FIX 5: rejeita nomes genéricos mesmo no fluxo de "aguardando nome"
            val envName = rawName.takeIf {
                it.isNotEmpty() && !BLOCKED_ENV_NAMES.contains(it.lowercase())
            } ?: ""
            if (envName.isNotEmpty()) {
                showToast("Criando '$envName'...")
                serviceScope.launch(Dispatchers.IO) {
                    val loc = getLastLocationBlocking()
                    val ok  = if (loc != null) writeEnvironmentToDb(envName, loc.latitude, loc.longitude, 100) else false
                    withContext(Dispatchers.Main) {
                        if (ok) speak("Pronto! Ambiente $envName criado.")
                        else speak("Não consegui criar o ambiente.")
                    }
                }
            } else {
                // Nome ainda genérico — pede novamente (loop de até 1 tentativa)
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
                    serviceScope.launch(Dispatchers.IO) {
                        val ok = writeTriggerToDb(title, result.triggerContent ?: "", envName)
                        withContext(Dispatchers.Main) {
                            if (ok) {
                                showToast("Anotado! Vou te lembrar de $title em $envName ✓")
                                speak("Anotado! Vou te lembrar de $title quando chegar em $envName.")
                            } else {
                                showToast("Não encontrei o ambiente '$envName'")
                                speak("Não encontrei o local $envName.")
                            }
                        }
                    }
                } else {
                    showToast("Diga: 'lembra de X quando chegar em Y'")
                    speak("Não entendi. Diga: lembra de X quando chegar em Y.")
                }
            }
            "create_environment" -> {
                val rawName = result.environment ?: ""
                // FIX 5: rejeita nomes genéricos (ambiente, local, aqui…) como null
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
                    // Nome válido → cria ambiente diretamente no SQLite + registra geofence
                    showToast("Criando '$envName'...")
                    serviceScope.launch(Dispatchers.IO) {
                        val loc = getLastLocationBlocking()
                        val ok  = if (loc != null) writeEnvironmentToDb(envName, loc.latitude, loc.longitude, 100) else false
                        withContext(Dispatchers.Main) {
                            if (ok) speak("Pronto! Ambiente $envName criado.")
                            else speak("Não consegui criar o ambiente. Tente novamente.")
                        }
                    }
                }
            }
            else -> {
                showToast("Não entendi. Abra o Sopro para comandos avançados.")
                speak("Não entendi. Pressione novamente para tentar.")
            }
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
    // Escrita direta no SQLite — sem abrir o app, sem Flutter Engine
    // ─────────────────────────────────────────────────────────────────────────

    // Cria ambiente no banco usando o caminho gravado pelo Flutter em SharedPreferences.
    // Chamado de Dispatchers.IO; registerGeofence() é postado na main thread.
    private fun writeEnvironmentToDb(name: String, lat: Double, lon: Double, radius: Int): Boolean {
        return try {
            val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString("flutter.sopro_db_path", null) ?: run {
                    logToSupabase("floating_env_error",
                        mapOf("error" to "db_path_not_in_prefs_open_app_first"))
                    return false
                }
            val dbFile = File(dbPath)
            if (!dbFile.exists()) {
                logToSupabase("floating_env_error",
                    mapOf("error" to "db_file_not_found", "path" to dbPath))
                return false
            }
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                .use { db ->
                    val id  = UUID.randomUUID().toString()
                    val now = System.currentTimeMillis()
                    db.execSQL(
                        "INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                        arrayOf(id, name, lat, lon, radius.toDouble(), now)
                    )
                    // GMS addGeofences exige main thread
                    mainHandler.post { registerGeofence(id, name, lat, lon, radius.toDouble()) }
                    logToSupabase("floating_env_created",
                        mapOf("env_name" to name, "lat" to lat.toString(),
                              "lon" to lon.toString(), "id" to id))
                }
            true
        } catch (e: Exception) {
            Log.e(TAG, "writeEnvironmentToDb error: ${e.message}")
            logToSupabase("floating_env_error",
                mapOf("error" to (e.message ?: "unknown"), "name" to name))
            false
        }
    }

    // Cria trigger no banco buscando ambiente pelo nome (case-insensitive).
    // Retorna true se salvo, false se ambiente não encontrado ou erro.
    private fun writeTriggerToDb(title: String, content: String, envName: String): Boolean {
        return try {
            val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString("flutter.sopro_db_path", null) ?: run {
                    logToSupabase("floating_trigger_error",
                        mapOf("error" to "db_path_not_in_prefs_open_app_first"))
                    return false
                }
            val dbFile = File(dbPath)
            if (!dbFile.exists()) {
                logToSupabase("floating_trigger_error",
                    mapOf("error" to "db_file_not_found", "path" to dbPath))
                return false
            }
            var success = false
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                .use { db ->
                    val cursor = db.rawQuery(
                        "SELECT id FROM environments WHERE LOWER(name) = LOWER(?) LIMIT 1",
                        arrayOf(envName)
                    )
                    val envId = if (cursor.moveToFirst()) cursor.getString(0) else null
                    cursor.close()

                    if (envId == null) {
                        Log.w(TAG, "Ambiente '$envName' não encontrado")
                        logToSupabase("floating_trigger_error",
                            mapOf("error" to "ambiente_nao_encontrado", "env_name" to envName))
                        return@use
                    }
                    val id  = UUID.randomUUID().toString()
                    val now = System.currentTimeMillis()
                    db.execSQL(
                        "INSERT INTO triggers (id, environment_id, title, content, is_active, created_at) VALUES (?, ?, ?, ?, 1, ?)",
                        arrayOf(id, envId, title, content, now)
                    )
                    logToSupabase("floating_trigger_created",
                        mapOf("title" to title, "env_name" to envName, "id" to id))
                    success = true
                }
            success
        } catch (e: Exception) {
            Log.e(TAG, "writeTriggerToDb error: ${e.message}")
            logToSupabase("floating_trigger_error",
                mapOf("error" to (e.message ?: "unknown"), "env_name" to envName))
            false
        }
    }

    // Emoji representativo pelo nome do ambiente — melhora contexto visual.
    private fun detectEmoji(name: String): String {
        val n = name.lowercase()
        return when {
            n.contains("casa") || n.contains("lar") || n.contains("home")          -> "🏠"
            n.contains("trabalho") || n.contains("empresa") || n.contains("escritório") -> "🏢"
            n.contains("mercado") || n.contains("supermercado")                    -> "🛒"
            n.contains("farmácia") || n.contains("farmacia")                       -> "💊"
            n.contains("academia") || n.contains("ginásio")                        -> "🏋️"
            n.contains("escola") || n.contains("faculdade") || n.contains("universidade") -> "🎓"
            n.contains("banco")                                                    -> "🏦"
            n.contains("restaurante")                                              -> "🍽️"
            n.contains("padaria") || n.contains("café") || n.contains("cafe")     -> "☕"
            n.contains("parque")                                                   -> "🌳"
            n.contains("posto") || n.contains("mecânico")                         -> "⛽"
            else                                                                   -> "📍"
        }
    }

    // Registra geofence nativo — idêntico ao padrão do BootReceiver.kt.
    // Deve ser chamado na main thread (LocationServices.getGeofencingClient é thread-safe,
    // mas os callbacks do addGeofences são entregues na main thread).
    @SuppressLint("MissingPermission") // permissão verificada em getLastLocationBlocking()
    private fun registerGeofence(id: String, name: String, lat: Double, lon: Double, radius: Double) {
        getSharedPreferences(GeofenceReceiver.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(id, name).apply()

        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(lat, lon, radius.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0) // não dispara imediatamente ao registrar
            .addGeofence(geofence)
            .build()

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(
            this, id.hashCode(),
            Intent(this, GeofenceReceiver::class.java),
            flags
        )

        LocationServices.getGeofencingClient(this)
            .addGeofences(request, pendingIntent)
            .addOnSuccessListener { Log.d(TAG, "Geofence '$name' registrado ✓") }
            .addOnFailureListener { e -> Log.e(TAG, "Falha ao registrar geofence '$name': ${e.message}") }
    }

    // Obtém última localização GPS em modo bloqueante — chamado de Dispatchers.IO.
    // Retorna null se permissão negada ou GPS indisponível.
    @SuppressLint("MissingPermission")
    private fun getLastLocationBlocking(): android.location.Location? {
        if (ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.ACCESS_FINE_LOCATION)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "ACCESS_FINE_LOCATION não concedido")
            return null
        }
        return try {
            Tasks.await(
                LocationServices.getFusedLocationProviderClient(this).lastLocation,
                10_000L, TimeUnit.MILLISECONDS
            )
        } catch (e: Exception) {
            Log.w(TAG, "getLastLocationBlocking falhou: ${e.message}")
            null
        }
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
