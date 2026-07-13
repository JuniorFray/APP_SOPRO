package com.sopro.sopro

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.*
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.view.*
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Tasks
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.LoggerConfiguration
import com.sopro.sopro.logging.SessionManager
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource

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

    // ── Correlation ID do ciclo de voz ativo (main thread only) ──────────────
    private var voiceCorrelationId: String? = null

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

        Logger.info("service_started", feature = "floating_voice", action = "onCreate",
            payload = mapOf("android_sdk" to Build.VERSION.SDK_INT.toString()))

        // SessionManager deve ser init antes de qualquer Logger.* para que device_id esteja disponível
        Logger.debug("session_manager_init_start", feature = "floating_voice", action = "onCreate")
        try {
            SessionManager.init(this)
        } catch (e: Exception) {
            logException("session_manager_init", e)
            throw e
        }
        Logger.debug("session_manager_init_done", feature = "floating_voice", action = "onCreate")

        // SYSTEM_ALERT_WINDOW é pré-requisito do overlay — sem ela o addView() falha
        Logger.debug("checking_overlay_permission", feature = "floating_voice", action = "onCreate")
        if (!Settings.canDrawOverlays(this)) {
            Logger.warn("overlay_permission_denied", feature = "floating_voice", action = "onCreate",
                payload = mapOf("permission" to "SYSTEM_ALERT_WINDOW"))
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "overlay_permission_denied"))
            stopSelf(); return
        }
        Logger.debug("overlay_permission_granted", feature = "floating_voice", action = "onCreate")

        // Android 14+ (API 34+): RECORD_AUDIO deve estar concedido em runtime ANTES de
        // startForeground() com serviceType=microphone; sem ela o sistema lança SecurityException.
        // Camada defensiva — a permissão já deveria ter sido solicitada pela UI (SettingsScreen).
        Logger.debug("checking_record_audio_permission", feature = "floating_voice", action = "onCreate")
        if (android.content.pm.PackageManager.PERMISSION_GRANTED !=
            androidx.core.content.ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.RECORD_AUDIO)) {
            Logger.warn("microphone_permission_denied_at_start", feature = "floating_voice",
                action = "onCreate", payload = mapOf("permission" to "RECORD_AUDIO"))
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "record_audio_permission_denied"))
            stopSelf(); return
        }
        Logger.debug("record_audio_permission_granted", feature = "floating_voice", action = "onCreate")

        // startForeground() deve ser chamado o mais cedo possível no onCreate() para evitar
        // ANR no Android 16 (API 36), que aplica limite de 5 s para promoção a foreground.
        // 3-arg: obrigatório para targetSdk >= 34 quando foregroundServiceType está declarado.
        // SecurityException: RECORD_AUDIO ausente ou FOREGROUND_SERVICE_MICROPHONE ausente.
        // IllegalStateException: ForegroundServiceStartNotAllowedException (API 31+, background-start).
        Logger.debug("starting_foreground", feature = "floating_voice", action = "onCreate",
            payload = mapOf("notif_id" to NOTIF_ID.toString(), "sdk" to Build.VERSION.SDK_INT.toString()))
        val fgsNotification = try {
            buildSilentNotification()
        } catch (e: Exception) {
            logException("build_notification", e)
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "build_notification_failed"))
            stopSelf(); return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, fgsNotification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIF_ID, fgsNotification)
            }
        } catch (e: SecurityException) {
            Logger.error("fgs_security_exception", feature = "floating_voice", action = "onCreate",
                exception = e, payload = mapOf("cause" to (e.message ?: "unknown")))
            logException("start_foreground", e)
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "fgs_security_exception"))
            stopSelf(); return
        } catch (e: IllegalStateException) {
            // Cobre ForegroundServiceStartNotAllowedException (API 31+, subclasse de IllegalStateException)
            Logger.error("fgs_illegal_state_exception", feature = "floating_voice", action = "onCreate",
                exception = e, payload = mapOf("cause" to (e.message ?: "unknown")))
            logException("start_foreground", e)
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "fgs_illegal_state"))
            stopSelf(); return
        } catch (e: Exception) {
            Logger.error("fgs_unexpected_exception", feature = "floating_voice", action = "onCreate",
                exception = e, payload = mapOf("cause" to (e.message ?: "unknown")))
            logException("start_foreground", e)
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "fgs_unexpected_exception"))
            stopSelf(); return
        }

        Logger.info("foreground_started", feature = "floating_voice", action = "startForeground",
            payload = mapOf("notif_id" to NOTIF_ID.toString()))

        // TTS nativo — onInit() é chamado assincronamente após init
        Logger.debug("tts_init_start", feature = "floating_voice", action = "onCreate")
        try {
            tts = TextToSpeech(this, this)
        } catch (e: Exception) {
            logException("tts_init", e)
            throw e
        }
        Logger.debug("tts_init_requested", feature = "floating_voice", action = "onCreate",
            payload = mapOf("note" to "onInit_callback_is_async"))

        // SpeechRecognizer deve ser criado na main thread — onCreate() já é main
        Logger.debug("init_speech_recognizer_start", feature = "floating_voice", action = "onCreate")
        try {
            initSpeechRecognizer()
        } catch (e: Exception) {
            logException("speech_init", e)
            throw e
        }

        Logger.debug("create_overlay_start", feature = "floating_voice", action = "onCreate")
        try {
            createOverlayButton()
        } catch (e: Exception) {
            logException("overlay_create", e)
            Logger.info("service_stopping", feature = "floating_voice", action = "onCreate",
                payload = mapOf("reason" to "overlay_create_failed"))
            stopSelf(); return
        }
        Logger.debug("overlay_created", feature = "floating_voice", action = "onCreate")

        (applicationContext as Application).registerActivityLifecycleCallbacks(lifecycleCallbacks)
        Logger.info("service_created", feature = "floating_voice", action = "onCreate")
    }

    // START_NOT_STICKY: se o processo for morto após um crash inesperado, o Android NÃO reinicia
    // o serviço automaticamente — evita crash loop que levaria o sistema a force-stop o app.
    // O usuário reativa o botão manualmente pelo toggle nas Configurações.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            Logger.info("service_start_command", feature = "floating_voice", action = "onStartCommand",
                payload = mapOf("flags" to flags.toString(), "start_id" to startId.toString()))
        } catch (e: Exception) {
            logException("service_start_command", e)
        }
        return START_NOT_STICKY
    }

    // FIX 4: seleciona melhor voz pt-BR offline e ajusta velocidade/tom após init assíncrono
    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Logger.warn("tts_init_failed", feature = "floating_voice", action = "tts_init",
                payload = mapOf("status" to status.toString()))
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
            Logger.debug("tts_voice_selected", feature = "floating_voice", action = "tts_init",
                payload = mapOf("voice_name" to bestVoice.name, "quality" to bestVoice.quality.toString()))
        } else {
            Logger.debug("tts_voice_default", feature = "floating_voice", action = "tts_init")
        }

        // FIX 4b: velocidade levemente reduzida + tom ligeiramente mais alto = mais claro
        tts?.setSpeechRate(0.95f)
        tts?.setPitch(1.05f)
    }

    override fun onDestroy() {
        try {
            Logger.info("service_destroying", feature = "floating_voice", action = "onDestroy")
            serviceScope.cancel()
            (applicationContext as Application).unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
            // SpeechRecognizer.destroy() deve ser chamado na main thread
            speechRecognizer?.destroy()
            speechRecognizer = null
            rippleAnimators.forEach { it.cancel() }
            mainHandler.removeCallbacksAndMessages(null)
            tts?.stop(); tts?.shutdown(); tts = null
            removeOverlayButton()
            Logger.debug("overlay_removed", feature = "floating_voice", action = "onDestroy")
            Logger.info("foreground_stopped", feature = "floating_voice", action = "onDestroy")
            Logger.info("service_destroyed", feature = "floating_voice", action = "onDestroy")
        } catch (e: Exception) {
            logException("service_destroy", e)
        } finally {
            super.onDestroy()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SpeechRecognizer — criação e listener
    // ─────────────────────────────────────────────────────────────────────────

    private fun initSpeechRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Logger.warn("speech_recognizer_unavailable", feature = "floating_voice",
                action = "init_speech_recognizer")
            return
        }
        Logger.debug("speech_recognition_available", feature = "floating_voice",
            action = "init_speech_recognizer")
        Logger.debug("creating_speech_recognizer", feature = "floating_voice",
            action = "init_speech_recognizer")
        try {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        } catch (e: Exception) {
            logException("speech_create", e)
            throw e
        }
        Logger.debug("speech_recognizer_created", feature = "floating_voice",
            action = "init_speech_recognizer")

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {

            // Reconhecedor pronto — inicia animação de escuta
            override fun onReadyForSpeech(params: Bundle?) {
                try {
                    Logger.debug("speech_ready", feature = "floating_voice", action = "stt",
                        correlationId = voiceCorrelationId)
                    startRippleAnimations()
                } catch (e: Exception) { logException("speech_ready", e) }
            }

            // Usuário começou a falar
            override fun onBeginningOfSpeech() {
                try {
                    Logger.trace("speech_began", feature = "floating_voice", action = "stt",
                        correlationId = voiceCorrelationId)
                } catch (e: Exception) { logException("speech_begin", e) }
            }

            // Usuário parou de falar — muda visual para "processando"
            override fun onEndOfSpeech() {
                try {
                    Logger.debug("speech_end_of_speech", feature = "floating_voice", action = "stt",
                        correlationId = voiceCorrelationId)
                    showProcessingState()
                } catch (e: Exception) { logException("speech_end", e) }
            }

            // Resultado final — classifica via Gemini ou usa diretamente como nome
            override fun onResults(results: Bundle?) {
                try { // stage: speech_results
                isListening = false
                val text = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (text.isNullOrBlank()) {
                    Logger.warn("speech_no_result", feature = "floating_voice", action = "stt",
                        correlationId = voiceCorrelationId)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                    revertButtonAppearance()
                    speak("Não ouvi nada. Segure e tente novamente.")
                    return
                }

                Logger.info("speech_final_result", feature = "floating_voice", action = "stt",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("speech_result" to text) else null,
                    correlationId = voiceCorrelationId)

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

                if (statePrefs.getString(KEY_VOICE_STATE, null) == "awaiting_env_confirm") {
                    val syntheticResult = FloatVoiceResult(
                        intent         = "awaiting_env_confirm",
                        environment    = null,
                        triggerTitle   = null,
                        triggerContent = null,
                        transcript     = text,
                    )
                    revertButtonAppearance()
                    executeVoiceResult(syntheticResult)
                    return
                }

                if (statePrefs.getString(KEY_VOICE_STATE, null) == "awaiting_env_for_trigger") {
                    val syntheticResult = FloatVoiceResult(
                        intent         = "awaiting_env_for_trigger",
                        environment    = null,
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
                } catch (e: Exception) { logException("speech_results", e) }
            }

            // Erro de reconhecimento — exibe mensagem amigável
            override fun onError(error: Int) {
                try { // stage: speech_error
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
                Logger.warn("speech_error", feature = "floating_voice", action = "stt",
                    payload = mapOf("code" to error.toString(), "message" to msg),
                    correlationId = voiceCorrelationId)
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
                revertButtonAppearance()
                speak(msg)
                } catch (e: Exception) { logException("speech_error", e) }
            }

            // Resultado parcial — registrado em trace para diagnóstico de STT
            override fun onPartialResults(partial: Bundle?) {
                val text = partial
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    Logger.trace("speech_partial", feature = "floating_voice", action = "stt",
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("transcript" to text) else null,
                        correlationId = voiceCorrelationId)
                }
            }

            // Callbacks de sinal — não utilizados
            override fun onRmsChanged(rmsdB: Float)           {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEvent(type: Int, params: Bundle?)  {}
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Notificação foreground (IMPORTANCE_LOW — Android 14+ exige mínimo LOW para FGS válido)
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildSilentNotification(): Notification {
        Logger.debug("build_notification_start", feature = "floating_voice", action = "foreground_notification",
            payload = mapOf("channel_id" to CHANNEL_ID))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                // IMPORTANCE_LOW: não emite som, mas é válido para FGS no Android 14+.
                // IMPORTANCE_MIN causava IllegalArgumentException ao vincular o canal a FGS do tipo microphone.
                Logger.debug("creating_notification_channel", feature = "floating_voice",
                    action = "foreground_notification",
                    payload = mapOf("channel_id" to CHANNEL_ID, "importance" to "IMPORTANCE_LOW"))
                try {
                    nm.createNotificationChannel(
                        NotificationChannel(CHANNEL_ID, "Sopro — Segundo plano",
                            NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) }
                    )
                } catch (e: IllegalArgumentException) {
                    logException("notification_channel", e); throw e
                } catch (e: Exception) {
                    logException("notification_channel", e); throw e
                }
                Logger.debug("notification_channel_created", feature = "floating_voice",
                    action = "foreground_notification",
                    payload = mapOf("channel_id" to CHANNEL_ID))
            }
        }
        val notification = try {
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.notification_icon)
                .setContentTitle("Sopro")
                .setContentText("Botão de voz ativo")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setSilent(true)
                .build()
        } catch (e: Exception) {
            logException("notification_display", e); throw e
        }
        Logger.debug("notification_created", feature = "floating_voice", action = "foreground_notification",
            payload = mapOf("channel_id" to CHANNEL_ID, "notif_id" to NOTIF_ID.toString()))
        return notification
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Criação da janela overlay
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun createOverlayButton() {
        // Android 11+ (API 30+): WindowManager deve ser obtido via createWindowContext() com
        // display explícito. Usar getSystemService() direto do Service context retorna um
        // WindowManager sem associação de display, causando BadTokenException no addView()
        // em Android 14/15 com edge-to-edge enforcement. createWindowContext() associa o
        // contexto ao display físico default e ao tipo TYPE_APPLICATION_OVERLAY antes do
        // addView(), eliminando o token inválido.
        windowManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val dm = getSystemService(DisplayManager::class.java)
            val display = dm.getDisplay(Display.DEFAULT_DISPLAY)!!
            createWindowContext(display, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
                .getSystemService(Context.WINDOW_SERVICE) as WindowManager
        } else {
            getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }

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
        Logger.debug("adding_overlay_view", feature = "floating_voice", action = "create_overlay",
            payload = mapOf("container_size_px" to containerPx.toString(), "layout_type" to layoutType.toString()))
        try {
            windowManager?.addView(container, params)
            Logger.debug("overlay_view_added", feature = "floating_voice", action = "create_overlay")
        } catch (e: Exception) {
            logException("overlay_add_view", e)
            throw e
        }
    }

    private fun circleDrawable(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL; setColor(color)
    }

    private fun removeOverlayButton() {
        containerView?.let {
            try { windowManager?.removeView(it) } catch (e: Exception) {
                Logger.warn("overlay_remove_failed", feature = "floating_voice", exception = e)
            }
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
                    try { windowManager?.updateViewLayout(containerView, p) } catch (e: Exception) {
                        Logger.trace("overlay_update_failed", feature = "floating_voice", exception = e)
                        logException("overlay_update", e)
                    }
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
                    Logger.debug("speech_cancelled", feature = "floating_voice", action = "stt",
                        correlationId = voiceCorrelationId)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
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
            Logger.warn("microphone_permission_denied", feature = "floating_voice",
                action = "start_listen", payload = mapOf("permission" to "RECORD_AUDIO"))
            return
        }

        if (speechRecognizer == null) {
            showToast("Reconhecedor de voz não disponível")
            return
        }

        voiceCorrelationId = CorrelationManager.beginOperation("voice")

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
        }

        try {
            Logger.debug("starting_speech_listener", feature = "floating_voice", action = "start_listen",
                correlationId = voiceCorrelationId)
            speechRecognizer?.startListening(intent)
            isListening = true

            // Beep curto (120 ms) confirma ativação do microfone ao usuário
            try {
                val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 30)
                toneGen.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                mainHandler.postDelayed({ toneGen.release() }, 200L)
            } catch (e: Exception) {
                Logger.warn("tone_generator_failed", feature = "floating_voice",
                    action = "start_listen", exception = e, correlationId = voiceCorrelationId)
            }

            animateButtonScale(from = 1.0f, to = 1.3f)
            btnView?.background = circleDrawable(0xFFFF2244.toInt())
            Logger.info("speech_started", feature = "floating_voice", action = "start_listen",
                correlationId = voiceCorrelationId)
        } catch (e: Exception) {
            Logger.error("speech_start_failed", feature = "floating_voice", action = "start_listen",
                exception = e, correlationId = voiceCorrelationId)
            logException("speech_start", e)
            showToast("Erro ao acessar microfone")
            isListening = false
            CorrelationManager.endOperation("voice")
            voiceCorrelationId = null
            revertButtonAppearance()
        }
    }

    // Encerra a captura — onEndOfSpeech → onResults ou onError disparam automaticamente
    private fun stopListeningAndProcess() {
        if (!isListening) return
        speechRecognizer?.stopListening()
        // isListening será false quando onResults ou onError disparar
        Logger.debug("speech_stop_requested", feature = "floating_voice", action = "stt",
            correlationId = voiceCorrelationId)
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
        val corrId = CorrelationManager.correlationIdFor("voice")

        Logger.info("gemini_request_preparing", feature = "floating_voice", action = "gemini",
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("transcript" to transcript) else null,
            correlationId = corrId)

        val apiKey = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GEMINI_API, "") ?: ""

        if (apiKey.isEmpty()) {
            Logger.warn("gemini_api_key_missing", feature = "floating_voice", action = "gemini",
                correlationId = corrId)
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                speak("Chave da API não configurada. Abra o Sopro uma vez.")
            }
            return
        }

        // Lê ambientes direto do SQLite — garante nomes exatos do banco no prompt
        val envNames = readEnvironmentNamesFromDb()
        val envCtx = if (envNames.isNotEmpty()) "Ambientes: $envNames" else ""
        val prompt = """JSON apenas, sem markdown.
Schemas:
create_trigger: {"intent":"create_trigger","environment":"Casa","trigger":{"title":"ligar para medico","content":""}}
create_environment: {"intent":"create_environment","environment":{"name":"Farmacia"}}
delete_environment: {"intent":"delete_environment","environment":"Trabalho"}
delete_trigger: {"intent":"delete_trigger","environment":"Mercado","title":"comprar leite"}
unknown: {"intent":"unknown"}
Exemplos create_trigger: "me lembre de X em Y", "preciso de X em Y", "nao esquecer X em Y", "quando chegar em Y, X"
Exemplos delete_trigger: "ja fiz X", "pode apagar X de Y", "remover X de Y"
$envCtx
Texto: $transcript""".trimIndent()

        val body = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("parts", JSONArray().apply {
                        put(JSONObject().put("text", prompt))
                    })
                })
            })
            put("generationConfig", JSONObject().apply {
                put("temperature", 0); put("maxOutputTokens", 1024)
            })
        }.toString()

        var responseBody = ""
        val geminiStart = System.currentTimeMillis()
        Logger.info("gemini_request_sending", feature = "floating_voice", action = "gemini",
            payload = mapOf("endpoint" to GEMINI_ENDPOINT, "body_length" to body.length.toString()),
            correlationId = corrId)
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
            responseBody = if (code == 200) {
                conn.inputStream.readBytes().toString(Charsets.UTF_8)
            } else {
                conn.errorStream?.readBytes()?.toString(Charsets.UTF_8) ?: ""
            }
            conn.disconnect()

            val geminiDuration = System.currentTimeMillis() - geminiStart
            if (code != 200) {
                Logger.warn("gemini_http_error", feature = "floating_voice", action = "gemini",
                    durationMs = geminiDuration,
                    payload = mapOf("http_code" to code.toString(),
                        "response_preview" to responseBody.take(200)),
                    correlationId = corrId)
                FloatVoiceResult(null, null, null, null, transcript, error = "http_$code")
            } else {
                Logger.info("gemini_response_received", feature = "floating_voice", action = "gemini",
                    durationMs = geminiDuration,
                    payload = mapOf("http_code" to code.toString(),
                        "response_length" to responseBody.length.toString()),
                    correlationId = corrId)
                try {
                    parseGeminiResponse(responseBody, transcript)
                } catch (e: Exception) {
                    logException("gemini_response", e)
                    FloatVoiceResult(null, null, null, null, transcript, error = "response_parse: ${e.message}")
                }
            }
        } catch (e: Exception) {
            val geminiDuration = System.currentTimeMillis() - geminiStart
            Logger.error("gemini_request_failed", feature = "floating_voice", action = "gemini",
                durationMs = geminiDuration,
                exception = e,
                payload = mapOf("response_preview" to responseBody.take(200)),
                correlationId = corrId)
            logException("gemini_request", e)
            FloatVoiceResult(null, null, null, null, transcript, error = e.message)
        }

        withContext(Dispatchers.Main) {
            Logger.debug("gemini_result_dispatching", feature = "floating_voice", action = "gemini",
                payload = mapOf("intent" to (result.intent ?: "null"),
                    "has_error" to (result.error != null).toString()),
                correlationId = corrId)
            revertButtonAppearance()
            executeVoiceResult(result)
        }
    }

    private fun parseGeminiResponse(raw: String, transcript: String): FloatVoiceResult {
        val corrId = CorrelationManager.correlationIdFor("voice")
        return try {
            val text = JSONObject(raw)
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts").getJSONObject(0)
                .getString("text")
                .replace(Regex("```[a-zA-Z]*\\n?"), "").replace("```", "").trim()

            val jsonStart = text.indexOf('{')
            val jsonEnd = text.lastIndexOf('}')
            val cleanJson = if (jsonStart >= 0 && jsonEnd > jsonStart)
                text.substring(jsonStart, jsonEnd + 1)
            else text
            val parsed = JSONObject(cleanJson)
            val intent = parsed.optString("intent", "unknown")

            if (intent == "unknown") {
                Logger.warn("intent_unknown", feature = "floating_voice", action = "parse",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("gemini_response" to cleanJson) else null,
                    correlationId = corrId)
            } else {
                Logger.info("intent_detected", feature = "floating_voice", action = "parse",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("intent" to intent, "gemini_response" to cleanJson)
                    else mapOf("intent" to intent),
                    correlationId = corrId)
            }

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
                "delete_environment" -> FloatVoiceResult(
                    intent         = intent,
                    environment    = parsed.optString("environment").takeIf { it.isNotEmpty() },
                    triggerTitle   = null, triggerContent = null,
                    transcript     = transcript,
                )
                "delete_trigger" -> FloatVoiceResult(
                    intent         = intent,
                    environment    = parsed.optString("environment").takeIf { it.isNotEmpty() },
                    triggerTitle   = parsed.optString("title").takeIf { it.isNotEmpty() },
                    triggerContent = null,
                    transcript     = transcript,
                )
                else -> FloatVoiceResult(
                    intent         = "unknown",
                    environment    = null,
                    triggerTitle   = null, triggerContent = null,
                    transcript     = transcript,
                )
            }
        } catch (e: Exception) {
            Logger.error("gemini_parse_failed", feature = "floating_voice", action = "parse",
                exception = e, correlationId = corrId)
            logException("intent_parser", e)
            FloatVoiceResult(null, null, null, null, transcript, error = "parse_error: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execução do resultado — sempre na Main thread (via withContext(Main))
    // ─────────────────────────────────────────────────────────────────────────

    private fun executeVoiceResult(result: FloatVoiceResult) {
        try {
        if (result.error != null) {
            Logger.warn("voice_result_error", feature = "floating_voice", action = "execute",
                payload = mapOf("error" to result.error), correlationId = voiceCorrelationId)
            CorrelationManager.endOperation("voice")
            voiceCorrelationId = null
            showToast("Erro: ${result.error.take(60)}")
            speak("Não entendi. Pressione novamente para tentar.")
            return
        }

        val statePrefs = getSharedPreferences(FLOAT_STATE_PREFS, Context.MODE_PRIVATE)
        val voiceState = statePrefs.getString(KEY_VOICE_STATE, null)
        val stateSetAt = statePrefs.getLong("voice_state_set_at", 0L)
        val stateExpired = System.currentTimeMillis() - stateSetAt > 30_000L
        if (stateExpired && voiceState != null) {
            statePrefs.edit().remove(KEY_VOICE_STATE).remove("voice_state_set_at").apply()
        }

        // Se estava aguardando nome de ambiente, usa transcript como nome.
        // NÃO reenvia ao Gemini — transcript vem direto do SpeechRecognizer (onResults).
        if (voiceState == VAL_AWAITING_NAME && !stateExpired) {
            statePrefs.edit().remove(KEY_VOICE_STATE).remove("voice_state_set_at").apply()
            val rawName = result.transcript?.trim() ?: ""
            // FIX 5: rejeita nomes genéricos mesmo no fluxo de "aguardando nome"
            val envName = rawName.takeIf {
                it.isNotEmpty() && !BLOCKED_ENV_NAMES.contains(it.lowercase())
            } ?: ""
            if (envName.isNotEmpty()) {
                showToast("Criando '$envName'...")
                serviceScope.launch(Dispatchers.IO) {
                    val loc = getLastLocationBlocking()
                    val lat = loc?.latitude ?: 0.0
                    val lon = loc?.longitude ?: 0.0
                    val ok = if (lat != 0.0 && lon != 0.0) writeEnvironmentToDb(envName, lat, lon, 100) else false
                    withContext(Dispatchers.Main) {
                        if (ok) speak("Pronto! Ambiente $envName criado.")
                        else speak("Não consegui criar o ambiente.")
                        CorrelationManager.endOperation("voice")
                        voiceCorrelationId = null
                    }
                }
            } else {
                // Nome ainda genérico — pede novamente (loop de até 1 tentativa)
                statePrefs.edit()
                    .putString(KEY_VOICE_STATE, VAL_AWAITING_NAME)
                    .putLong("voice_state_set_at", System.currentTimeMillis())
                    .apply()
                showToast("Esse não parece um nome de lugar. Tente um nome mais específico.")
                speak("Qual é o nome do lugar? Por exemplo: casa, trabalho ou academia.")
                mainHandler.postDelayed({ showToast("Segure o botão para gravar o nome.") }, 2500L)
            }
            return
        }

        if (voiceState == "awaiting_env_confirm" && !stateExpired) {
            val pendingTitle   = statePrefs.getString("pending_trigger_title", null) ?: ""
            val pendingContent = statePrefs.getString("pending_trigger_content", null) ?: ""
            val pendingEnv     = statePrefs.getString("pending_trigger_env", null) ?: ""
            statePrefs.edit()
                .remove(KEY_VOICE_STATE).remove("voice_state_set_at")
                .remove("pending_trigger_title").remove("pending_trigger_content")
                .remove("pending_trigger_env").apply()
            val text = (result.transcript ?: "").lowercase(java.util.Locale("pt", "BR"))
            val confirmed = listOf("sim", "pode", "cria", "quero").any { text.contains(it) }
            val denied    = listOf("nao", "não", "nope", "cancela", "deixa").any { text.contains(it) }
            when {
                confirmed && pendingEnv.isNotEmpty() -> {
                    showToast("Criando ambiente e lembrete...")
                    serviceScope.launch(Dispatchers.IO) {
                        val loc = getLastLocationBlocking()
                        val lat = loc?.latitude ?: 0.0
                        val lon = loc?.longitude ?: 0.0
                        if (lat != 0.0 && lon != 0.0) {
                            val envOk     = writeEnvironmentToDb(pendingEnv, lat, lon, 100)
                            val triggerOk = if (envOk) writeTriggerToDb(pendingTitle, pendingContent, pendingEnv) else false
                            withContext(Dispatchers.Main) {
                                if (triggerOk) speak("Pronto! Ambiente $pendingEnv criado e lembrete '$pendingTitle' registrado.")
                                else           speak("Ambiente criado, mas não consegui salvar o lembrete.")
                                CorrelationManager.endOperation("voice")
                                voiceCorrelationId = null
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                speak("Não foi possível obter sua localização.")
                                CorrelationManager.endOperation("voice")
                                voiceCorrelationId = null
                            }
                        }
                    }
                }
                denied -> {
                    speak("Tudo bem, lembrete cancelado.")
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
                else -> {
                    speak("Não entendi. Diga 'sim' para criar o ambiente ou 'não' para cancelar.")
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
            }
            return
        }

        if (voiceState == "awaiting_env_for_trigger" && !stateExpired) {
            val pendingTitle = statePrefs.getString("pending_trigger_title", null) ?: ""
            statePrefs.edit()
                .remove(KEY_VOICE_STATE).remove("voice_state_set_at")
                .remove("pending_trigger_title").apply()
            val envName = result.transcript?.trim() ?: ""
            if (envName.isNotEmpty() && pendingTitle.isNotEmpty()) {
                showToast("Salvando lembrete em $envName...")
                serviceScope.launch(Dispatchers.IO) {
                    val ok = writeTriggerToDb(pendingTitle, "", envName)
                    withContext(Dispatchers.Main) {
                        if (ok) speak("Anotado! Vou te lembrar de $pendingTitle quando chegar em $envName.")
                        else    speak("Não encontrei o ambiente $envName. Quer que eu crie agora?")
                        CorrelationManager.endOperation("voice")
                        voiceCorrelationId = null
                    }
                }
            } else {
                speak("Não entendi. Tente: 'lembra de X quando chegar em Y'.")
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
            }
            return
        }

        Logger.info("intent_dispatched", feature = "floating_voice", action = "execute",
            payload = mapOf("intent" to (result.intent ?: "null")),
            correlationId = voiceCorrelationId)

        when (result.intent) {
            "create_trigger" -> {
                val title = result.triggerTitle ?: ""
                val resolvedEnv = if (result.environment.isNullOrEmpty()) {
                    val transcript = result.transcript ?: ""
                    val patterns = listOf(
                        Regex("(?:chegar\\s+(?:n[ao]|em)\\s+)([\\wÀ-ú\\s]+?)(?:\\s*$|,|\\.)", RegexOption.IGNORE_CASE),
                        Regex("(?:n[ao]\\s+)([\\wÀ-ú]+)\\s*$", RegexOption.IGNORE_CASE)
                    )
                    patterns.firstNotNullOfOrNull { regex ->
                        regex.find(transcript)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.length > 2 }
                    }
                } else {
                    result.environment
                }
                if (resolvedEnv.isNullOrEmpty()) {
                    speak("Em qual ambiente devo salvar esse lembrete?")
                    statePrefs.edit()
                        .putString("pending_trigger_title", result.triggerTitle)
                        .putString(KEY_VOICE_STATE, "awaiting_env_for_trigger")
                        .putLong("voice_state_set_at", System.currentTimeMillis())
                        .apply()
                    return
                }
                val resolvedEnvCapitalized = resolvedEnv.trim()
                    .split(" ")
                    .joinToString(" ") { word ->
                        word.lowercase(java.util.Locale("pt", "BR"))
                            .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
                    }
                if (title.isNotEmpty()) {
                    serviceScope.launch(Dispatchers.IO) {
                        val start = System.currentTimeMillis()
                        val ok = writeTriggerToDb(title, result.triggerContent ?: "", resolvedEnvCapitalized)
                        withContext(Dispatchers.Main) {
                            if (ok) {
                                Logger.info("command_executed", feature = "floating_voice", action = "execute",
                                    payload = mapOf("command" to "create_trigger"),
                                    correlationId = voiceCorrelationId)
                                showToast("Anotado! Vou te lembrar de $title em $resolvedEnvCapitalized ✓")
                                speak("Anotado! Vou te lembrar de $title quando chegar em $resolvedEnvCapitalized.")
                            } else {
                                showToast("Não encontrei o ambiente '$resolvedEnvCapitalized'")
                                statePrefs.edit()
                                    .putString("pending_trigger_title", result.triggerTitle)
                                    .putString("pending_trigger_env", resolvedEnvCapitalized)
                                    .putString(KEY_VOICE_STATE, "awaiting_env_confirm")
                                    .putLong("voice_state_set_at", System.currentTimeMillis())
                                    .apply()
                                speak("Não encontrei o ambiente $resolvedEnvCapitalized. Quer que eu crie agora?")
                            }
                            CorrelationManager.endOperation("voice")
                            voiceCorrelationId = null
                        }
                    }
                } else {
                    showToast("Diga: 'lembra de X quando chegar em Y'")
                    speak("Não entendi. Diga: lembra de X quando chegar em Y.")
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
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
                    statePrefs.edit()
                        .putString(KEY_VOICE_STATE, VAL_AWAITING_NAME)
                        .putLong("voice_state_set_at", System.currentTimeMillis())
                        .apply()
                    showToast("Qual é o nome do ambiente?")
                    speak("Qual é o nome do ambiente?")
                    // Delay de 2000 ms antes de pedir a gravação — evita que o mic
                    // capture este áudio TTS como entrada da próxima gravação
                    mainHandler.postDelayed({
                        showToast("Segure o botão para gravar o nome.")
                    }, 2000L)
                } else {
                    Logger.debug("create_environment_start", feature = "floating_voice",
                        action = "execute",
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("environment_name" to envName) else null,
                        correlationId = voiceCorrelationId)
                    // Nome válido → cria ambiente diretamente no SQLite + registra geofence
                    showToast("Criando '$envName'...")
                    serviceScope.launch(Dispatchers.IO) {
                        val loc = getLastLocationBlocking()
                        val lat = loc?.latitude ?: 0.0
                        val lon = loc?.longitude ?: 0.0
                        val ok = if (lat != 0.0 && lon != 0.0) {
                            writeEnvironmentToDb(envName, lat, lon, 100)
                        } else {
                            Logger.warn("gps_unavailable", feature = "floating_voice",
                                action = "location",
                                payload = if (LoggerConfiguration.debugLogging)
                                    mapOf("environment_name" to envName) else null,
                                correlationId = CorrelationManager.correlationIdFor("voice"))
                            withContext(Dispatchers.Main) {
                                speak("Não foi possível obter sua localização. Abra o app e defina manualmente.")
                            }
                            false
                        }
                        withContext(Dispatchers.Main) {
                            if (ok) {
                                Logger.info("command_executed", feature = "floating_voice", action = "execute",
                                    payload = mapOf("command" to "create_environment"),
                                    correlationId = voiceCorrelationId)
                                speak("Pronto! Ambiente $envName criado.")
                            } else if (lat != 0.0 || lon != 0.0) speak("Não consegui criar o ambiente. Tente novamente.")
                            CorrelationManager.endOperation("voice")
                            voiceCorrelationId = null
                        }
                    }
                }
            }
            "delete_environment" -> {
                val envName = result.environment ?: ""
                if (envName.isNotEmpty()) {
                    serviceScope.launch(Dispatchers.IO) {
                        val ok = deleteEnvironmentFromDb(envName)
                        withContext(Dispatchers.Main) {
                            if (ok) {
                                Logger.info("command_executed", feature = "floating_voice", action = "execute",
                                    payload = mapOf("command" to "delete_environment"),
                                    correlationId = voiceCorrelationId)
                                speak("Ambiente $envName removido.")
                            } else speak("Não encontrei o ambiente $envName.")
                            CorrelationManager.endOperation("voice")
                            voiceCorrelationId = null
                        }
                    }
                } else {
                    speak("Qual ambiente você quer remover?")
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
            }
            "delete_trigger" -> {
                val envName = result.environment ?: ""
                val title   = result.triggerTitle
                serviceScope.launch(Dispatchers.IO) {
                    val ok = deleteTriggerFromDb(envName, title)
                    withContext(Dispatchers.Main) {
                        if (ok) {
                            Logger.info("command_executed", feature = "floating_voice", action = "execute",
                                payload = mapOf("command" to "delete_trigger"),
                                correlationId = voiceCorrelationId)
                            speak("Lembrete removido.")
                        }
                        CorrelationManager.endOperation("voice")
                        voiceCorrelationId = null
                    }
                }
            }
            else -> {
                showToast("Não entendi. Abra o Sopro para comandos avançados.")
                speak("Não entendi. Pressione novamente para tentar.")
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
            }
        }
        } catch (e: Exception) { logException("command_dispatch", e) }
    }

    // Lê nomes de ambientes direto do SQLite — garante nomes exatos no prompt Gemini.
    // Chamado de Dispatchers.IO, portanto acesso ao DB é seguro.
    private fun readEnvironmentNamesFromDb(): List<String> {
        val dbFile = findDbFile() ?: return emptyList()
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
            // Tenta com deleted_at; se coluna não existir cai no catch e tenta sem WHERE
            val cursor = try {
                db.rawQuery("SELECT name FROM environments WHERE deleted_at IS NULL", null)
            } catch (e: Exception) {
                Logger.debug("sqlite_read_fallback", feature = "floating_voice", action = "db_read",
                    payload = mapOf("reason" to "deleted_at_column_missing"),
                    exception = e,
                    correlationId = CorrelationManager.correlationIdFor("voice"))
                db.rawQuery("SELECT name FROM environments", null)
            }
            val names = mutableListOf<String>()
            cursor.use { while (it.moveToNext()) names.add(it.getString(0)) }
            Logger.debug("sqlite_read_environments", feature = "floating_voice", action = "db_read",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("count" to names.size.toString()),
                correlationId = CorrelationManager.correlationIdFor("voice"))
            names
        } catch (e: Exception) {
            Logger.warn("sqlite_read_failed", feature = "floating_voice", action = "db_read",
                durationMs = System.currentTimeMillis() - start,
                exception = e,
                correlationId = CorrelationManager.correlationIdFor("voice"))
            logException("gemini_request", e)
            emptyList()
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
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
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null)
        Logger.debug("sqlite_write_environment_start", feature = "floating_voice", action = "db_write",
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("name" to name) else null,
            correlationId = corrId)
        val resolvedPath = dbPath ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(resolvedPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to resolvedPath),
                correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val envNameCapitalized = name.trim()
                .split(" ")
                .joinToString(" ") { word ->
                    word.lowercase(java.util.Locale("pt", "BR"))
                        .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
                }
            val id  = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            db.execSQL(
                "INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                arrayOf(id, envNameCapitalized, lat, lon, radius.toDouble(), now)
            )
            // GMS addGeofences exige main thread
            mainHandler.post { registerGeofence(id, envNameCapitalized, lat, lon, radius.toDouble()) }
            Logger.info("environment_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envNameCapitalized, "id" to id)
                else mapOf("id" to id),
                correlationId = corrId)
            true
        } catch (e: Exception) {
            Logger.error("sqlite_write_environment_failed", feature = "floating_voice",
                action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                exception = e,
                payload = if (LoggerConfiguration.debugLogging) mapOf("name" to name) else null,
                correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Cria trigger no banco buscando ambiente pelo nome (case-insensitive).
    // Retorna true se salvo, false se ambiente não encontrado ou erro.
    private fun writeTriggerToDb(title: String, content: String, envName: String): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "write_trigger"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "write_trigger"),
                correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val cursor = db.rawQuery(
                "SELECT id FROM environments WHERE LOWER(name) = LOWER(?) LIMIT 1",
                arrayOf(envName)
            )
            val envId = if (cursor.moveToFirst()) cursor.getString(0) else null
            cursor.close()
            if (envId == null) {
                Logger.warn("environment_not_found", feature = "floating_voice", action = "db_read",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("environment_name" to envName) else null,
                    correlationId = corrId)
                getSharedPreferences(FLOAT_STATE_PREFS, Context.MODE_PRIVATE).edit()
                    .putString("pending_trigger_title", title)
                    .putString("pending_trigger_content", content)
                    .putString("pending_trigger_env", envName)
                    .putString(KEY_VOICE_STATE, "awaiting_env_confirm")
                    .putLong("voice_state_set_at", System.currentTimeMillis())
                    .apply()
                return false
            }
            val id  = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            db.execSQL(
                "INSERT INTO triggers (id, environment_id, title, content, is_active, created_at) VALUES (?, ?, ?, ?, 1, ?)",
                arrayOf(id, envId, title, content, now)
            )
            Logger.info("trigger_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("title" to title, "environment_name" to envName, "id" to id)
                else mapOf("id" to id),
                correlationId = corrId)
            true
        } catch (e: Exception) {
            Logger.error("sqlite_write_trigger_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                exception = e,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("title" to title, "environment_name" to envName) else null,
                correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Remove ambiente e todos os seus triggers do banco (case-insensitive por nome).
    // Retorna true se removido, false se não encontrado ou erro.
    private fun deleteEnvironmentFromDb(envName: String): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "delete_env"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "delete_env"),
                correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val envNameCapitalized = envName.trim()
                .split(" ")
                .joinToString(" ") { word ->
                    word.lowercase(java.util.Locale("pt", "BR"))
                        .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
                }
            val cursor = db.rawQuery(
                "SELECT id FROM environments WHERE LOWER(name) = LOWER(?) LIMIT 1",
                arrayOf(envNameCapitalized)
            )
            val envId = if (cursor.moveToFirst()) cursor.getString(0) else null
            cursor.close()
            if (envId == null) {
                Logger.warn("environment_not_found", feature = "floating_voice", action = "db_read",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("environment_name" to envNameCapitalized) else null,
                    correlationId = corrId)
                mainHandler.post { speak("Não encontrei o ambiente $envNameCapitalized. Verifique o nome e tente novamente.") }
                return false
            }
            // Remove triggers primeiro (FK), depois o ambiente
            db.execSQL("DELETE FROM triggers WHERE environment_id = ?", arrayOf(envId))
            db.execSQL("DELETE FROM environments WHERE id = ?", arrayOf(envId))
            Logger.info("environment_deleted", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envNameCapitalized, "id" to envId)
                else mapOf("id" to envId),
                correlationId = corrId)
            getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis())
                .apply()
            true
        } catch (e: Exception) {
            Logger.error("sqlite_delete_environment_failed", feature = "floating_voice",
                action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                exception = e,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envName) else null,
                correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Remove trigger(s) do banco.
    // triggerTitle não nulo → remove por título parcial (LIKE) no ambiente.
    // triggerTitle nulo    → remove TODOS os triggers do ambiente.
    private fun deleteTriggerFromDb(envName: String, triggerTitle: String?): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "delete_trigger"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "delete_trigger"),
                correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val envNameCapitalized = envName.trim()
                .split(" ")
                .joinToString(" ") { word ->
                    word.lowercase(java.util.Locale("pt", "BR"))
                        .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
                }
            if (triggerTitle != null) {
                val stmt = db.compileStatement(
                    "DELETE FROM triggers WHERE LOWER(title) LIKE LOWER(?) AND environment_id IN " +
                    "(SELECT id FROM environments WHERE LOWER(name) = LOWER(?))"
                )
                stmt.bindString(1, "%${triggerTitle}%")
                stmt.bindString(2, envNameCapitalized)
                val rowsAffected = stmt.executeUpdateDelete()
                if (rowsAffected == 0) {
                    Logger.warn("trigger_not_found", feature = "floating_voice", action = "db_write",
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("title" to triggerTitle, "environment_name" to envNameCapitalized)
                        else null,
                        correlationId = corrId)
                    mainHandler.post { speak("Não encontrei esse lembrete em $envNameCapitalized.") }
                }
            } else {
                db.execSQL(
                    "DELETE FROM triggers WHERE environment_id IN " +
                    "(SELECT id FROM environments WHERE LOWER(name) = LOWER(?))",
                    arrayOf(envNameCapitalized)
                )
            }
            Logger.info("trigger_deleted", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envNameCapitalized,
                        "title" to (triggerTitle ?: "all"))
                else null,
                correlationId = corrId)
            true
        } catch (e: Exception) {
            Logger.error("sqlite_delete_trigger_failed", feature = "floating_voice",
                action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                exception = e,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envName) else null,
                correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
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

        try {
            LocationServices.getGeofencingClient(this)
                .addGeofences(request, pendingIntent)
                .addOnSuccessListener {
                    Logger.info("geofence_registered", feature = "floating_voice", action = "geofence",
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("name" to name, "id" to id) else mapOf("id" to id))
                }
                .addOnFailureListener { e ->
                    Logger.error("geofence_registration_failed", feature = "floating_voice",
                        action = "geofence",
                        exception = e,
                        payload = if (LoggerConfiguration.debugLogging)
                            mapOf("name" to name, "id" to id) else mapOf("id" to id))
                    logException("geofence_register", e)
                }
        } catch (e: SecurityException) {
            logException("geofence_register", e)
        } catch (e: Exception) {
            logException("geofence_register", e)
        }
    }

    // Obtém localização GPS em modo bloqueante — chamado de Dispatchers.IO.
    // Pipeline: lastLocation (cache passivo) → getCurrentLocation (fix ativo) → prefs cache.
    // Retorna null somente se permissão negada e as três etapas falharem.
    @SuppressLint("MissingPermission")
    private fun getLastLocationBlocking(): android.location.Location? {
        if (ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.ACCESS_FINE_LOCATION)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Logger.warn("location_permission_denied", feature = "floating_voice", action = "location",
                payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
            return null
        }

        // Verifica GPS antes de tentar FusedLocationProvider — evita null silencioso
        Logger.debug("gps_check_started", feature = "floating_voice", action = "location")
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        if (!locationManager.isLocationEnabled) {
            val providerGps     = locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
            val providerNetwork = locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
            Logger.debug("gps_disabled", feature = "floating_voice", action = "location",
                payload = mapOf(
                    "gps_enabled"      to "false",
                    "provider_gps"     to providerGps.toString(),
                    "provider_network" to providerNetwork.toString()
                ))
            // GPS desligado — pula FusedProvider e usa prefs cache diretamente
            val prefs   = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
            val latBits = prefs.getLong("flutter.last_known_lat", 0L)
            val lonBits = prefs.getLong("flutter.last_known_lon", 0L)
            if (latBits == 0L && lonBits == 0L) {
                Logger.warn("location_unavailable", feature = "floating_voice", action = "location",
                    payload = mapOf("reason" to "gps_disabled_no_cache"))
                return null
            }
            Logger.debug("location_cache_used", feature = "floating_voice", action = "location",
                payload = mapOf("reason" to "gps_disabled"))
            return android.location.Location("prefs_cache").also { loc ->
                loc.latitude  = java.lang.Double.longBitsToDouble(latBits)
                loc.longitude = java.lang.Double.longBitsToDouble(lonBits)
            }
        }
        Logger.debug("gps_enabled", feature = "floating_voice", action = "location")

        val fused = LocationServices.getFusedLocationProviderClient(this)
        val start = System.currentTimeMillis()

        // Etapa 1: lastLocation — zero bateria, usa cache passivo do sistema
        val cached: android.location.Location? = try {
            Tasks.await(fused.lastLocation, 5_000L, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            Logger.warn("location_fetch_failed", feature = "floating_voice", action = "location",
                durationMs = System.currentTimeMillis() - start, exception = e)
            null
        }
        if (cached != null) {
            Logger.debug("location_last_location_hit", feature = "floating_voice", action = "location",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("source" to "last_location"))
            saveLocationToPrefs(cached)
            return cached
        }
        Logger.debug("location_last_location_null", feature = "floating_voice", action = "location",
            durationMs = System.currentTimeMillis() - start)

        // Etapa 2: getCurrentLocation — single-shot ativo, solicita fix fresco ao hardware
        Logger.debug("location_current_location_requested", feature = "floating_voice", action = "location")
        val fresh: android.location.Location? = try {
            val cts = CancellationTokenSource()
            val result = Tasks.await(
                fused.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token),
                8_000L, TimeUnit.MILLISECONDS
            )
            if (result != null) {
                Logger.debug("location_current_location_success", feature = "floating_voice",
                    action = "location", durationMs = System.currentTimeMillis() - start)
                saveLocationToPrefs(result)
            } else {
                Logger.warn("location_current_location_failed", feature = "floating_voice",
                    action = "location", durationMs = System.currentTimeMillis() - start,
                    payload = mapOf("reason" to "null_result"))
            }
            result
        } catch (e: java.util.concurrent.TimeoutException) {
            Logger.warn("location_current_location_timeout", feature = "floating_voice",
                action = "location", durationMs = System.currentTimeMillis() - start)
            null
        } catch (e: Exception) {
            Logger.warn("location_current_location_failed", feature = "floating_voice",
                action = "location", durationMs = System.currentTimeMillis() - start, exception = e)
            null
        }
        if (fresh != null) return fresh

        // Etapa 3: prefs cache — último fix válido gravado em sessão anterior (leitura correta via getLong)
        val prefs = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
        val latBits = prefs.getLong("flutter.last_known_lat", 0L)
        val lonBits = prefs.getLong("flutter.last_known_lon", 0L)
        if (latBits == 0L && lonBits == 0L) {
            Logger.warn("location_unavailable", feature = "floating_voice", action = "location",
                durationMs = System.currentTimeMillis() - start)
            return null
        }
        Logger.debug("location_cache_used", feature = "floating_voice", action = "location",
            durationMs = System.currentTimeMillis() - start)
        return android.location.Location("prefs_cache").also { loc ->
            loc.latitude  = java.lang.Double.longBitsToDouble(latBits)
            loc.longitude = java.lang.Double.longBitsToDouble(lonBits)
        }
    }

    // Persiste localização válida para fallback em execuções futuras.
    private fun saveLocationToPrefs(location: android.location.Location) {
        getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE).edit()
            .putLong("flutter.last_known_lat", java.lang.Double.doubleToRawLongBits(location.latitude))
            .putLong("flutter.last_known_lon", java.lang.Double.doubleToRawLongBits(location.longitude))
            .apply()
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
    // logException — padrão único de service_exception para Supabase remoto.
    // Inclui stage, exception, message, stack (400 chars), android_sdk,
    // manufacturer e model. Nunca lança exceção — totalmente protegido.
    // ─────────────────────────────────────────────────────────────────────────

    private fun logException(stage: String, e: Throwable) {
        try {
            Logger.error("service_exception", feature = "floating_voice", action = stage,
                payload = mapOf(
                    "stage"        to stage,
                    "exception"    to e.javaClass.name,
                    "message"      to (e.message ?: ""),
                    "stack"        to e.stackTraceToString().take(400),
                    "android_sdk"  to Build.VERSION.SDK_INT.toString(),
                    "manufacturer" to Build.MANUFACTURER,
                    "model"        to Build.MODEL
                ))
        } catch (_: Exception) { /* proteção: nunca lançar durante log */ }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Supabase logging — fire-and-forget, mantido para integração futura com AppLogger Kotlin
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
            Logger.trace("supabase_send_failed", feature = "floating_voice", exception = e)
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
