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
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.*
import android.util.Base64
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
// Fluxo (Sprint Unificação da Captura): SEGURAR → MediaRecorder grava M4A →
// SOLTAR → Gemini ÁUDIO classifica → trigger/ambiente no SQLite direto.
//
// Objetivo da Sprint: Home e Overlay usam EXATAMENTE o mesmo pipeline de captura —
// MediaRecorder (AAC-LC, 8 kHz, 12 kbps, mesmo codec do pacote `record` no Dart) →
// Gemini Áudio. O DEDO é o único fim de gravação: sem VAD, sem end-of-speech, sem
// timeout de silêncio. Enquanto o botão está pressionado, o áudio continua sendo
// gravado (pausas e silêncios NÃO interrompem — Regras 1-4).
//
// Etapa12 (revertida por esta Sprint): usava SpeechRecognizer + Gemini Texto.
// SpeechRecognizer permanece no projeto, porém DESACOPLADO da captura (reservado
// para ativação por palavra-chave/hotword futura), não participa mais dos comandos.
//
// FIX (mantidos das etapas anteriores):
//   FIX 3: speak() salva timestamp → Flutter skip TTS se floating falou há < 10 s.
//   FIX 4: TTS seleciona melhor voz pt-BR offline; setSpeechRate(0.95) + setPitch(1.05).
//   FIX 5: nomes genéricos (ambiente, local, lugar…) rejeitados → pede nome real.
//
// IPC com o app:
//   FloatingVoiceService escreve em "sopro_float_state" → KEY_PENDING_INTENT.
//   Mudanças de dados (ambiente sem coords, wipe total) chamam
//   MainActivity.notifyDataChanged() → push "dataChanged" para a engine viva
//   atualizar a UI na hora; com o app fechado, o cold start (initState) cobre.
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
        // Etapa 3 — chave Groq (STT nuvem) via bridge SharedPreferences (Home escreve).
        private const val KEY_GROQ_API       = "flutter.groq_api_key"
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

        // Fase 1 — estado de confirmação por voz para operações destrutivas.
        // Enquanto ativo, a próxima fala é interpretada como resposta sim/não
        // (via parseYesNo), não como comando novo enviado ao Gemini.
        internal const val VAL_AWAITING_CONFIRM = "awaiting_destructive_confirm"

        // Resolução Inteligente de Localização (paridade com a Home) — enquanto
        // ativo, a próxima fala é a resposta sim/não para usar o GPS atual ao
        // criar um ambiente. Impede create_environment antes da resolução.
        internal const val VAL_AWAITING_LOCATION_CONFIRM = "awaiting_location_confirm"

        // Lista de compras — enquanto ativo, a próxima fala escolhe em QUAL mercado
        // (dentre 2+) os itens pendentes serão gravados. Armazena pending_shopping_items
        // e pending_market_names nas mesmas prefs de estado.
        internal const val VAL_AWAITING_MARKET_CHOICE = "awaiting_market_choice"

        // Fase 1 — transcrições "de relógio" que o STT devolve quando não houve
        // fala real (ex.: "00:00", "0:00", "00.00"). Tratadas como ausência de fala.
        private val CLOCK_LIKE_REGEX = Regex("""^\s*\d{1,2}[:.]\d{2}\s*$""")
        // Detecta ao menos um caractere de fala (letra ou dígito Unicode).
        private val WORD_CHAR_REGEX = Regex("""[\p{L}\p{N}]""")

        // Fase 1 — vocabulário sim/não para confirmação por voz. O negativo tem
        // prioridade sobre o positivo ("não pode" resolve como não).
        // "pode" cru é ambíguo: "pode ser"=sim, mas "pode encerrar/cancelar"=
        // desistir. Removido o "pode" solto; mantidos os positivos reais
        // ("pode ser"; "pode confirmar" casa em "confirmar"). O cancelamento é
        // interceptado ANTES por isCancelPhrase (mesmo fix do Home).
        private val YES_WORDS = listOf(
            "sim", "pode ser", "cria", "criar", "quero", "claro", "isso", "confirma",
            "confirmar", "positivo", "manda", "ok", "okay", "certo", "exato",
            "exatamente", "afirmativo", "bora", "vai",
        )
        private val NO_WORDS = listOf(
            "nao", "não", "cancela", "cancelar", "deixa", "para", "negativo",
            "nunca", "jamais", "esquece", "nada",
        )

        // Supabase — mesma URL/chave do AppLogger.dart (publishable key, INSERT-only RLS)
        private const val SUPABASE_URL =
            "https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs"
        private const val SUPABASE_KEY =
            "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"

        // Endpoint Gemini — mesmo modelo usado pelo Dart (AppConstants.geminiModel)
        private const val GEMINI_ENDPOINT =
            "https://generativelanguage.googleapis.com/v1beta/models/" +
            "gemini-2.5-flash:generateContent"

        // Etapa 3 — STT nuvem (Groq, OpenAI-compatible). Mesmo modelo do Home.
        private const val GROQ_STT_ENDPOINT =
            "https://api.groq.com/openai/v1/audio/transcriptions"

        // GATE ADAPTATIVO (noise floor) — substitui os limiares FIXOS 1500/3500.
        // MediaRecorder não expõe stream, então lemos getMaxAmplitude() (0..32767)
        // por polling. Medimos o ruído ambiente nos primeiros ~500 ms e detectamos
        // fala só quando a amplitude supera noiseFloor * fator. Amplitude é LINEAR,
        // então "+8 dB" = fator 10^(8/20) ≈ 2.5 e "+12 dB" = fator ≈ 4.0.
        private const val CALIB_SAMPLES     = 5    // ~500 ms (polls de 100 ms)
        private const val SPEECH_FACTOR     = 2.19 // fala = ruído * 2.19 (≈ +6.8 dB) (BUG 3: -15% p/ sussurro)
        private const val PEAK_FACTOR       = 3.24 // pico exigido = ruído * 3.24 (≈ +10.2 dB) (BUG 3: -15%)
        private const val MIN_NOISE_FLOOR   = 300  // piso: evita estouro em silêncio digital
        private const val MIN_SPEECH_FRAMES = 3    // ≈ 300 ms (polls de 100 ms)

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

    // ── SpeechRecognizer — DESACOPLADO da captura (Sprint Unificação) ─────────
    // Mantido no projeto para hotword futura; NÃO participa mais da captura de
    // comandos. Criado em onCreate() e destruído em onDestroy() na main thread.
    private var speechRecognizer: SpeechRecognizer? = null

    // Estágio 1 — estado da conversa por voz encapsulado (antes: chaves cruas de
    // prefs espalhadas). lazy: só toca prefs após o Context estar pronto (onCreate).
    private val conversationState by lazy { OverlayConversationState(this) }

    // Estágio 2 — dependências das Skills do overlay, montadas 1x. Os helpers de
    // DB/fala seguem private: chegam às Skills só como referências de função.
    private val skillContext by lazy {
        OverlaySkillContext(
            scope                 = serviceScope,
            writeEnvironment      = { name, lat, lon, radius -> writeEnvironmentToDb(name, lat, lon, radius) },
            writeTrigger          = { title, content, env -> writeTriggerToDb(title, content, env) },
            writeShopping         = { items, market -> writeShoppingItemsToDb(items, market) },
            // Etapa 2 — atualizações + lembrete por tempo (escrita + agendamento nativos).
            updateTrigger         = { env, title, newTitle, content -> updateTriggerInDb(env, title, newTitle, content) },
            updateEnvironment     = { name, radius -> updateEnvironmentInDb(name, radius) },
            createReminder        = { title, millis, repeat, days, alert ->
                val id = writeReminderToDb(title, millis, repeat, days, alert)
                if (id != null) { ReminderScheduler.scheduleExact(this, id, millis); true } else false
            },
            deleteEnvironment     = { env -> deleteEnvironmentFromDb(env) },
            deleteTrigger         = { env, title -> deleteTriggerFromDb(env, title) },
            deleteAllEnvironments = { deleteAllEnvironmentsFromDb() },
            isBlockedName         = { BLOCKED_ENV_NAMES.contains(it.lowercase()) },
            speak                 = { text -> speak(text) },
            endVoice              = { endVoice() },
            correlationId         = { voiceCorrelationId },
        )
    }

    // ── Captura de áudio (MediaRecorder) — pipeline unificado com a Home ──────
    // Grava M4A (AAC-LC, 8 kHz, 12 kbps) — MESMO codec/sampleRate/bitRate do Dart.
    // isRecording é o estado de gravação; o DEDO decide o fim (sem VAD/timeout).
    private var mediaRecorder: MediaRecorder? = null
    private var audioFile: File? = null
    private var isRecording = false
    private var recordStartMs = 0L

    // GATE ADAPTATIVO — estado do gate de energia (poll de getMaxAmplitude).
    private var speechFrames = 0        // polls acima do limiar adaptativo
    private var maxAmp = 0              // pico linear observado na sessão
    private var noiseAccum = 0L         // soma das amplitudes na calibração
    private var calibSamples = 0        // polls já usados p/ medir o ruído
    private var noiseFloor = 0.0        // ruído ambiente medido (0 até calibrar)
    private var speechThreshold = 0.0   // noiseFloor * SPEECH_FACTOR
    private var amplitudePoller: Runnable? = null

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

        // Fonte única de texto de voz (prompt + persona), mesmo asset lido pelo Home.
        // Carrega cedo para que OverlayPrompt/OverlayPersona já tenham o cache pronto.
        VoiceContent.ensureLoaded(this)

        // Prewarm da voz Piper (OverlayTts) em background: copia os assets e carrega
        // o modelo fora da main thread, para a 1ª fala não pagar esse custo em runtime.
        // applicationContext evita segurar o Service caso ele seja destruído durante a carga.
        val appCtx = applicationContext
        serviceScope.launch { OverlayTts.ensureReady(appCtx) }

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

        // Sprint Unificação: SpeechRecognizer fica DESACOPLADO da captura. Nenhum
        // RecognitionListener de comando é registrado — o reconhecedor é criado
        // apenas para uso futuro (hotword). A captura de comandos é 100%
        // MediaRecorder (startAudioCapture/stopAudioCaptureAndProcess).
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
    // Tratamento de toque — SEGURAR grava, SOLTAR processa, ARRASTAR move.
    //
    // Sprint Unificação: o DEDO é o único fim de gravação (igual à Home).
    //   - ACTION_DOWN agenda o início da gravação após um hold curto (evita gravar
    //     ao apenas encostar/arrastar). Enquanto o dedo segue pressionado, o
    //     MediaRecorder continua gravando — silêncio e pausas NÃO interrompem.
    //   - ACTION_MOVE reposiciona; se o gesto virar arraste ANTES de começar a
    //     gravar, cancela o início agendado (arrastar = mover, não falar).
    //   - ACTION_UP encerra e processa (ou dá dica se foi toque curto).
    //   - ACTION_CANCEL (evento de sistema) descarta a gravação sem enviar.
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragStartX     = event.rawX
                dragStartY     = event.rawY
                initParamX     = layoutParams?.x ?: 0
                initParamY     = layoutParams?.y ?: 0
                pressStartTime = System.currentTimeMillis()

                // Hold curto (250 ms) antes de gravar — desambigua toque/arraste de fala
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                val run = Runnable { startAudioCapture() }
                recordingStartRunnable = run
                mainHandler.postDelayed(run, 250L)
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = (event.rawX - dragStartX).toInt()
                val dy = (event.rawY - dragStartY).toInt()
                // Se ainda NÃO começou a gravar e o dedo passou do slop, é arraste:
                // cancela o início agendado para não gravar durante o reposicionamento.
                if (!isRecording && recordingStartRunnable != null) {
                    val slop = dpToPx(14)
                    if (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop) {
                        recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                        recordingStartRunnable = null
                    }
                }
                // SEMPRE reposiciona o botão (gravando ou não — arrastar não corta fala)
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

                // Salva posição final — sempre, independente de ter gravado
                layoutParams?.let { p ->
                    getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                        .edit().putInt(KEY_BTN_X, p.x).putInt(KEY_BTN_Y, p.y).apply()
                }

                val duration = System.currentTimeMillis() - pressStartTime
                when {
                    // Estava gravando → encerra e envia ao Gemini
                    isRecording     -> stopAudioCaptureAndProcess()
                    // Toque curto sem gravação → dica de uso
                    duration < 300L -> showToast("Segure para gravar")
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                // Evento de sistema — descarta a gravação sem processar
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null
                if (isRecording) cancelAudioCapture()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Captura de áudio (MediaRecorder) — pipeline unificado com a Home
    //
    // Grava M4A (AAC-LC, 8 kHz, 12 kbps): MESMO codec/sampleRate/bitRate do pacote
    // `record` no Dart. Sem VAD, sem end-of-speech, sem timeout — só o dedo encerra.
    // ─────────────────────────────────────────────────────────────────────────

    @Suppress("DEPRECATION") // MediaRecorder() sem context é usado em SDK < 31
    private fun startAudioCapture() {
        if (isRecording) return

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            showToast("Permissão de microfone necessária")
            Logger.warn("microphone_permission_denied", feature = "floating_voice",
                action = "capture", payload = mapOf("permission" to "RECORD_AUDIO"))
            return
        }

        voiceCorrelationId = CorrelationManager.beginOperation("voice")
        val file = File(cacheDir, "sopro_overlay_voice.m4a")
        try { if (file.exists()) file.delete() } catch (_: Exception) {}

        val rec = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this)
            else MediaRecorder()
        } catch (e: Exception) {
            logException("recorder_create", e)
            revertButtonAppearance()
            CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            return
        }

        try {
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4) // container .m4a
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)    // AAC-LC
            rec.setAudioSamplingRate(8000)                          // 8 kHz — igual ao Dart
            rec.setAudioEncodingBitRate(12000)                      // 12 kbps — igual ao Dart
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec.start()
            mediaRecorder  = rec
            audioFile      = file
            isRecording    = true
            recordStartMs  = System.currentTimeMillis()

            // GATE ADAPTATIVO — poll de energia. Primeiros CALIB_SAMPLES medem o
            // ruído ambiente (noiseFloor); depois só contam frames acima de
            // noiseFloor * SPEECH_FACTOR. getMaxAmplitude() = pico desde a última leitura.
            speechFrames = 0; maxAmp = 0; noiseAccum = 0L; calibSamples = 0
            noiseFloor = 0.0; speechThreshold = 0.0
            val poll = object : Runnable {
                override fun run() {
                    if (!isRecording) return
                    val amp = try { mediaRecorder?.maxAmplitude ?: 0 } catch (_: Exception) { 0 }
                    if (amp > maxAmp) maxAmp = amp
                    if (calibSamples < CALIB_SAMPLES) {
                        // Janela de calibração: acumula ruído, NÃO detecta fala.
                        calibSamples++
                        noiseAccum += amp
                        if (calibSamples == CALIB_SAMPLES) {
                            noiseFloor = maxOf((noiseAccum / CALIB_SAMPLES).toDouble(),
                                MIN_NOISE_FLOOR.toDouble())
                            speechThreshold = noiseFloor * SPEECH_FACTOR
                        }
                    } else {
                        if (amp > speechThreshold) speechFrames++
                    }
                    mainHandler.postDelayed(this, 100L)
                }
            }
            amplitudePoller = poll
            // Início atrasado 250 ms: pula o beep de 120 ms para não sujar o ruído medido.
            mainHandler.postDelayed(poll, 250L)

            // Beep curto (120 ms) confirma ativação do microfone
            try {
                val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 30)
                toneGen.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                mainHandler.postDelayed({ toneGen.release() }, 200L)
            } catch (e: Exception) {
                Logger.warn("tone_generator_failed", feature = "floating_voice",
                    action = "capture", exception = e, correlationId = voiceCorrelationId)
            }

            startRippleAnimations()
            animateButtonScale(from = 1.0f, to = 1.3f)
            btnView?.background = circleDrawable(0xFFFF2244.toInt())
        } catch (e: Exception) {
            Logger.error("voice_capture_start_failed", feature = "floating_voice", action = "capture",
                exception = e, correlationId = voiceCorrelationId)
            logException("recorder_start", e)
            try { rec.release() } catch (_: Exception) {}
            mediaRecorder = null; audioFile = null; isRecording = false
            showToast("Erro ao acessar microfone")
            revertButtonAppearance()
            CorrelationManager.endOperation("voice"); voiceCorrelationId = null
        }
    }

    // Encerra a gravação. Regra 9: se muito curta / arquivo minúsculo (soltou
    // imediatamente), NÃO envia ao Gemini — responde OverlayPersona.notHeard.
    private fun stopAudioCaptureAndProcess() {
        if (!isRecording) return
        isRecording = false
        // HOTFIX SILÊNCIO — encerra o poll de energia da sessão.
        amplitudePoller?.let { mainHandler.removeCallbacks(it) }; amplitudePoller = null
        val durationMs = System.currentTimeMillis() - recordStartMs
        val file       = audioFile

        // MediaRecorder.stop() lança IllegalStateException se a gravação foi curta
        // demais (sem dados) — capturamos e tratamos como descarte.
        val stopped = try { mediaRecorder?.stop(); true } catch (e: Exception) {
            Logger.warn("voice_capture_stop_failed", feature = "floating_voice",
                action = "capture", exception = e, correlationId = voiceCorrelationId)
            false
        }
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        showProcessingState()

        val sizeBytes = try { file?.length() ?: 0L } catch (_: Exception) { 0L }

        // GATE ADAPTATIVO — fala = frames sustentados acima do limiar adaptativo E
        // pico >= noiseFloor * PEAK_FACTOR. Fallbacks (não bloqueiam por energia):
        //   - maxAmp==0 a sessão toda: device não reporta amplitude;
        //   - gravação curta demais p/ calibrar: cai no gate de duração/tamanho.
        val ampSupported = maxAmp > 0
        val calibrated = calibSamples >= CALIB_SAMPLES
        val hasSpeech = if (ampSupported && calibrated)
            (speechFrames >= MIN_SPEECH_FRAMES && maxAmp >= noiseFloor * PEAK_FACTOR)
        else true
        // Regra 9 + gate de energia: soltar imediato / áudio minúsculo / SEM FALA → não envia.
        if (!stopped || file == null || durationMs < 500L || sizeBytes < 800L || !hasSpeech) {
            try { file?.delete() } catch (_: Exception) {}
            revertButtonAppearance()
            // REGRA 3 — responder APENAS OverlayPersona.notHeard (toast extra removido).
            speak(OverlayPersona.notHeard)
            CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            return
        }

        serviceScope.launch { processAudioWithGemini(file) }
    }

    // Descarta a gravação atual (ACTION_CANCEL do sistema) sem enviar ao Gemini.
    private fun cancelAudioCapture() {
        if (!isRecording) return
        isRecording = false
        // HOTFIX SILÊNCIO — encerra o poll de energia.
        amplitudePoller?.let { mainHandler.removeCallbacks(it) }; amplitudePoller = null
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        try { audioFile?.delete() } catch (_: Exception) {}
        revertButtonAppearance()
        CorrelationManager.endOperation("voice"); voiceCorrelationId = null
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
    // Gemini Áudio — chamado exclusivamente de Dispatchers.IO (serviceScope).
    //
    // Sprint Unificação: envia o M4A gravado (inline_data base64) ao MESMO endpoint
    // do pipeline da Home. O Gemini transcreve E classifica em uma única chamada;
    // o campo "transcricao" alimenta result.transcript (usado pelos awaiting-states
    // e pelo fallback por regex do create_trigger).
    // ─────────────────────────────────────────────────────────────────────────

    private suspend fun processAudioWithGemini(file: File) {
        val corrId = CorrelationManager.correlationIdFor("voice")

        Logger.info("gemini_request_preparing", feature = "floating_voice", action = "gemini",
            correlationId = corrId)

        val apiKey = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GEMINI_API, "") ?: ""

        if (apiKey.isEmpty()) {
            Logger.warn("gemini_api_key_missing", feature = "floating_voice", action = "gemini",
                correlationId = corrId)
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                speak(OverlayPersona.apiKeyMissing)
                CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            }
            try { file.delete() } catch (_: Exception) {}
            return
        }

        // Lê o áudio e codifica em base64 (MESMO formato do pipeline da Home)
        val audioB64 = try {
            Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)
        } catch (e: Exception) {
            logException("audio_read", e)
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                speak(OverlayPersona.audioProcessingFailed)
                CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            }
            try { file.delete() } catch (_: Exception) {}
            return
        }

        // Lê ambientes direto do SQLite — garante nomes exatos do banco no prompt
        val envNames = readEnvironmentNamesFromDb()
        // BUG 2 — em estado de espera (confirmação sim/não, nome pendente, etc.),
        // NÃO usa o prompt de PLANO. Prompt mínimo só-transcrição; a decisão fica
        // 100% local (parseYesNo em executeVoiceResult). Nunca classifica confirmação.
        val awaitingState = hasActiveAwaitingState()
        if (awaitingState) {
            Logger.info("voice_confirmation_local", feature = "floating_voice",
                action = "confirm", payload = mapOf("surface" to "overlay"),
                correlationId = corrId) // LOG TEMPORÁRIO (BUG 2)
        }
        // Estágio 3 — prompt de PLANO isolado (texto byte-idêntico) em OverlayPrompt.
        val fullPrompt = OverlayPrompt.buildPlanPrompt(envNames)

        // Etapa 3 — STT unificado com o Home: no fluxo de PLANO, transcreve via Groq
        // (nuvem, whisper-large-v3-turbo) e manda TEXTO ao Gemini — mais rápido e mesmo
        // STT do Home. Fallback automático: Groq indisponível (sem chave/sem internet/
        // erro) → mantém o envio de ÁUDIO ao Gemini (comportamento anterior, sem
        // regressão). Estados de espera (sim/não, nome) seguem por áudio como antes.
        val groqText: String? = if (awaitingState) null else transcribeWithGroq(file, corrId)

        val parts = JSONArray()
        if (groqText != null) {
            // Mesma montagem do processTextAsPlan do Home: prompt + comando do usuário.
            parts.put(JSONObject().put("text",
                "$fullPrompt\n\nComando do usuario: \"$groqText\""))
        } else {
            // BUG 2 — prompt final: só-transcrição em espera, plano completo caso contrário.
            val prompt = if (awaitingState)
                """Transcreva EXATAMENTE o audio em pt-BR. Responda SO com JSON valido, sem markdown:
{"transcricao":"texto falado"}""".trimIndent()
            else fullPrompt
            parts.put(JSONObject().put("text", prompt))
            parts.put(JSONObject().put("inline_data", JSONObject()
                .put("mime_type", "audio/m4a").put("data", audioB64)))
        }

        val body = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply { put("parts", parts) })
            })
            put("generationConfig", JSONObject().apply {
                // Fase 2.2 REGRA 5 — remove limite artificial (era 1024, truncava planos
                // longos e causava "Unterminated string"). 2048 = mesmo teto da Home.
                put("temperature", 0); put("maxOutputTokens", 2048)
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
                FloatVoiceResult(null, null, null, null, null, error = "http_$code")
            } else {
                Logger.info("gemini_response_received", feature = "floating_voice", action = "gemini",
                    durationMs = geminiDuration,
                    payload = mapOf("http_code" to code.toString(),
                        "response_length" to responseBody.length.toString()),
                    correlationId = corrId)
                // Fase 2.2 — NÃO parseia aqui. HTTP 200 apenas marca sucesso; o PLANO
                // (actions[]) é interpretado por handleGeminiPlan(responseBody) na Main
                // thread, com parser robusto + prioridade destrutiva + logs temporários.
                FloatVoiceResult(null, null, null, null, null)
            }
        } catch (e: Exception) {
            val geminiDuration = System.currentTimeMillis() - geminiStart
            Logger.error("gemini_request_failed", feature = "floating_voice", action = "gemini",
                durationMs = geminiDuration,
                exception = e,
                payload = mapOf("response_preview" to responseBody.take(200)),
                correlationId = corrId)
            logException("gemini_request", e)
            FloatVoiceResult(null, null, null, null, null, error = e.message)
        }

        // Áudio temporário já não é necessário — remove (privacidade + espaço)
        try { file.delete() } catch (_: Exception) {}

        withContext(Dispatchers.Main) {
            Logger.debug("gemini_result_dispatching", feature = "floating_voice", action = "gemini",
                payload = mapOf("has_error" to (result.error != null).toString()),
                correlationId = corrId)
            revertButtonAppearance()
            // Fase 2.2 — dois caminhos: erro real de HTTP/rede/envelope segue o fluxo
            // de erro legado (executeVoiceResult trata error != null); HTTP 200 vai
            // para o novo interpretador de PLANO (paridade total com a Home).
            if (result.error != null) executeVoiceResult(result)
            else                      handleGeminiPlan(responseBody)
        }
    }

    // ── STT nuvem (Groq / Whisper) — Etapa 3, unifica com o Home ──────────────
    // Transcreve o M4A gravado via Groq (whisper-large-v3-turbo, OpenAI-compatible).
    // Retorna o texto (pt-BR) ou NULL em qualquer indisponibilidade (sem chave, sem
    // internet, timeout, status != 200, corpo vazio) — o chamador cai no envio de
    // ÁUDIO ao Gemini. Mesmo padrão HTTP nativo já usado pro Gemini; multipart/form-data
    // montado à mão (sem dependência extra). Privacidade: loga só duração/tamanho.
    private fun transcribeWithGroq(file: File, corrId: String?): String? {
        val key = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GROQ_API, "") ?: ""
        if (key.isEmpty()) return null

        val start = System.currentTimeMillis()
        var conn: HttpURLConnection? = null
        return try {
            val audio = file.readBytes()
            if (audio.isEmpty()) return null
            val boundary = "----soproGroq${System.nanoTime()}"
            // Cabeçalho multipart (campos + preâmbulo da parte do arquivo).
            val pre = buildString {
                append("--$boundary\r\n")
                append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
                append("whisper-large-v3-turbo\r\n")
                append("--$boundary\r\n")
                append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
                append("pt\r\n")
                append("--$boundary\r\n")
                append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
                append("text\r\n")
                append("--$boundary\r\n")
                append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
                append("Content-Type: audio/m4a\r\n\r\n")
            }.toByteArray(Charsets.UTF_8)
            val post = "\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8)

            conn = (URL(GROQ_STT_ENDPOINT).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000; readTimeout = 10_000; doOutput = true
                setRequestProperty("Authorization", "Bearer $key")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }
            conn.outputStream.use { out -> out.write(pre); out.write(audio); out.write(post) }

            val code = conn.responseCode
            if (code != 200) {
                Logger.warn("groq_stt_http", feature = "floating_voice", action = "groq_stt",
                    durationMs = System.currentTimeMillis() - start,
                    payload = mapOf("http_code" to code.toString()), correlationId = corrId)
                return null
            }
            // response_format=text → corpo é o texto puro. Não logamos o texto.
            val text = conn.inputStream.readBytes().toString(Charsets.UTF_8).trim()
            Logger.info("groq_stt_ok", feature = "floating_voice", action = "groq_stt",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("len" to text.length.toString()), correlationId = corrId)
            text.ifEmpty { null }
        } catch (e: Exception) {
            // Sem internet/timeout/etc. — silencioso; cai no fallback de áudio ao Gemini.
            Logger.info("groq_stt_unavailable", feature = "floating_voice", action = "groq_stt",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("reason" to (e.message ?: "exception")), correlationId = corrId)
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    // Fase 2.2 — parseGeminiResponse (schema antigo single-intent, com substring
    // indexOf('{')/lastIndexOf('}')) foi REMOVIDO. Motivo: violava a REGRA 1 (nunca
    // interpretar JSON por substring) e era a causa do "Unterminated string" ao cortar
    // strings truncadas. Substituído por parsePlanResponse + extractJsonObject (parser
    // balanceado e ciente de aspas). O schema legado continua suportado via
    // legacyIntentToAction, mantendo a compatibilidade (REGRA 10).

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
            speak(OverlayPersona.notUnderstoodPressAgain)
            return
        }

        // Estado capturado uma vez (mesma semântica dos antigos voiceState/stateExpired).
        val voiceState = conversationState.current
        val stateExpired = conversationState.isExpired
        if (stateExpired && voiceState != null) {
            conversationState.clearMarker()
        }
        // Estágio 4 — estado de espera ATIVO resolvido pelo Planner (null se expirou).
        val awaiting = OverlayPlanner.activeAwaiting(voiceState, stateExpired)

        // Cancelamento UNIVERSAL: em QUALQUER estado de espera ativo, uma frase de
        // desistência encerra de vez — antes de tratar como nome/sim-não/escolha.
        // Espelha o "cancel-first" do Home (_resolveEnvLocationTurn). Sem isso, os
        // estados de nome/escolha tratavam "cancela" como dado (criavam lixo).
        if (awaiting != null && isCancelPhrase(result.transcript ?: "")) {
            conversationState.clear()
            speak(OverlayPersona.cancelledOk)
            endVoice()
            return
        }

        // Se estava aguardando nome de ambiente, usa transcript como nome.
        // NÃO reenvia ao Gemini — transcript vem direto do SpeechRecognizer (onResults).
        if (awaiting == VAL_AWAITING_NAME) {
            conversationState.clear()
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
                        if (ok) speak(OverlayPersona.environmentCreatedReady(envName))
                        else speak(OverlayPersona.couldNotCreateEnvironment)
                        CorrelationManager.endOperation("voice")
                        voiceCorrelationId = null
                    }
                }
            } else {
                // Nome ainda genérico — pede novamente (loop de até 1 tentativa)
                conversationState.armAwaitingName()
                showToast("Esse não parece um nome de lugar. Tente um nome mais específico.")
                speak(OverlayPersona.askPlaceName)
                mainHandler.postDelayed({ showToast("Segure o botão para gravar o nome.") }, 2500L)
            }
            return
        }

        if (awaiting == OverlayConversationState.AWAITING_ENV_CONFIRM) {
            val pendingTitle   = conversationState.pendingTriggerTitle
            val pendingContent = conversationState.pendingTriggerContent
            val pendingEnv     = conversationState.pendingTriggerEnv
            // BUG #3: NÃO limpa antes de decidir — só após confirmar/negar/re-armar.
            // Antes, o clear() aqui fazia a resposta ambígua perder o estado e o
            // reprompt virar inútil (próxima fala já era comando novo).
            val text = (result.transcript ?: "").lowercase(java.util.Locale("pt", "BR"))
            val confirmed = listOf("sim", "pode", "cria", "quero").any { text.contains(it) }
            val denied    = listOf("nao", "não", "nope", "cancela", "deixa").any { text.contains(it) }
            when {
                confirmed && pendingEnv.isNotEmpty() -> {
                    conversationState.clear() // decisão tomada: consome o estado
                    showToast("Criando ambiente e lembrete...")
                    serviceScope.launch(Dispatchers.IO) {
                        val loc = getLastLocationBlocking()
                        val lat = loc?.latitude ?: 0.0
                        val lon = loc?.longitude ?: 0.0
                        if (lat != 0.0 && lon != 0.0) {
                            val envOk     = writeEnvironmentToDb(pendingEnv, lat, lon, 100)
                            val triggerOk = if (envOk) writeTriggerToDb(pendingTitle, pendingContent, pendingEnv) else false
                            withContext(Dispatchers.Main) {
                                if (triggerOk) speak(OverlayPersona.environmentAndReminderCreated(pendingEnv, pendingTitle))
                                else           speak(OverlayPersona.environmentCreatedReminderFailed)
                                CorrelationManager.endOperation("voice")
                                voiceCorrelationId = null
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                speak(OverlayPersona.locationUnavailable)
                                CorrelationManager.endOperation("voice")
                                voiceCorrelationId = null
                            }
                        }
                    }
                }
                denied -> {
                    conversationState.clear() // decisão tomada: consome o estado
                    speak(OverlayPersona.reminderCancelled)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
                else -> {
                    // Ambíguo: RE-ARMA o mesmo estado (renova o TTL de 30s) para o
                    // reprompt valer de verdade — a próxima fala volta a responder
                    // esta mesma pergunta em vez de virar um comando novo.
                    conversationState.armEnvConfirm(
                        pendingTitle, pendingEnv,
                        pendingContent.takeIf { it.isNotEmpty() },
                    )
                    speak(OverlayPersona.confirmCreateEnvironmentYesNo)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
            }
            return
        }

        if (awaiting == OverlayConversationState.AWAITING_ENV_FOR_TRIGGER) {
            val pendingTitle = conversationState.pendingTriggerTitle
            conversationState.clear()
            val envName = result.transcript?.trim() ?: ""
            if (envName.isNotEmpty() && pendingTitle.isNotEmpty()) {
                showToast("Salvando lembrete em $envName...")
                serviceScope.launch(Dispatchers.IO) {
                    val ok = writeTriggerToDb(pendingTitle, "", envName)
                    withContext(Dispatchers.Main) {
                        if (ok) speak(OverlayPersona.reminderSaved(pendingTitle, envName))
                        else    speak(OverlayPersona.environmentNotFoundCreate(envName))
                        CorrelationManager.endOperation("voice")
                        voiceCorrelationId = null
                    }
                }
            } else {
                speak(OverlayPersona.reminderExampleTry)
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
            }
            return
        }

        // Fase 1 — resposta de uma confirmação destrutiva pendente (sim/não).
        // Recupera a ação armazenada e executa apenas se a resposta for afirmativa.
        if (awaiting == VAL_AWAITING_CONFIRM) {
            val confirmIntent = conversationState.confirmIntent
            val confirmEnv    = conversationState.confirmEnv
            val confirmTitle  = conversationState.confirmTitle
            conversationState.clear()
            val answer = parseYesNo(result.transcript ?: "")
            if (answer == true) {
                Logger.info("voice_confirmation_yes", feature = "floating_voice",
                    action = "confirm", payload = mapOf("intent" to confirmIntent),
                    correlationId = voiceCorrelationId)
                performConfirmedDestructive(confirmIntent, confirmEnv, confirmTitle)
            } else {
                // não OU ambíguo → cancela (destrutivo nunca ocorre sem "sim")
                Logger.info("voice_confirmation_no", feature = "floating_voice",
                    action = "confirm",
                    payload = mapOf("intent" to confirmIntent,
                        "explicit" to (answer == false).toString()),
                    correlationId = voiceCorrelationId)
                speak(OverlayPersona.cancelledOk)
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
            }
            return
        }

        // Resolução Inteligente de Localização — resposta sim/não para usar o GPS
        // atual ao criar o ambiente pendente (paridade com o confirm_gps da Home).
        if (awaiting == VAL_AWAITING_LOCATION_CONFIRM) {
            val pendingName = conversationState.pendingEnvName
            conversationState.clear()
            val answer = parseYesNo(result.transcript ?: "")
            if (answer == true && pendingName.isNotEmpty()) {
                // SIM → cria na localização atual (mesmo caminho GPS de sempre).
                createEnvironmentWithGps(pendingName)
            } else {
                // NÃO/ambíguo → NÃO usa GPS; o endereço/local é resolvido no app
                // (overlay não possui geocoder). Orienta a abrir o Sopro.
                speak(OverlayPersona.openAppForAddress(pendingName))
                endVoice()
            }
            return
        }

        // Resposta a "em qual mercado?" — grava os itens pendentes no mercado escolhido.
        // Mesmo molde do bloco acima: lê o estado, consome, tenta casar a fala.
        if (awaiting == VAL_AWAITING_MARKET_CHOICE) {
            val itemsRaw = conversationState.pendingShoppingItems
            val namesRaw = conversationState.pendingMarketNames
            val items = itemsRaw.split("|").filter { it.isNotEmpty() }
            val marketNames = namesRaw.split("|").filter { it.isNotEmpty() }
            conversationState.clear()

            val choice = parseMarketChoice(result.transcript ?: "", marketNames)
            if (choice != null && items.isNotEmpty()) {
                val market = marketNames[choice]
                serviceScope.launch(Dispatchers.IO) {
                    val ok = AddShoppingItemSkill.execute(items, market, skillContext)
                    withContext(Dispatchers.Main) {
                        if (ok) speakTyped(confirmShoppingPhrase(items, market), TtsTone.SUCCESS)
                        else speakTyped(OverlayPersona.couldNotSaveNow, TtsTone.ERROR)
                        endVoice()
                    }
                }
            } else {
                // Não casou/ambíguo → regrava o MESMO estado (não perde os itens) e repergunta.
                conversationState.armMarketChoice(itemsRaw, namesRaw)
                speakTyped(OverlayPersona.marketNameRepeat, TtsTone.QUESTION)
                endVoice()
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
                    speak(OverlayPersona.askWhichEnvironmentForReminder)
                    conversationState.armEnvForTrigger(result.triggerTitle)
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
                        val ok = CreateTriggerSkill.execute(
                            resolvedEnvCapitalized, title, result.triggerContent ?: "", skillContext)
                        withContext(Dispatchers.Main) {
                            if (ok) {
                                Logger.info("command_executed", feature = "floating_voice", action = "execute",
                                    payload = mapOf("command" to "create_trigger"),
                                    correlationId = voiceCorrelationId)
                                showToast("Anotado! Vou te lembrar de $title em $resolvedEnvCapitalized ✓")
                                speak(OverlayPersona.reminderSaved(title, resolvedEnvCapitalized))
                            } else {
                                showToast("Não encontrei o ambiente '$resolvedEnvCapitalized'")
                                conversationState.armEnvConfirm(result.triggerTitle, resolvedEnvCapitalized)
                                speak(OverlayPersona.environmentNotFoundCreate(resolvedEnvCapitalized))
                            }
                            CorrelationManager.endOperation("voice")
                            voiceCorrelationId = null
                        }
                    }
                } else {
                    showToast("Diga: 'lembra de X quando chegar em Y'")
                    speak(OverlayPersona.reminderExampleSay)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
            }
            "add_shopping_item" -> {
                // Caminho legado single-intent (o fluxo normal usa executePlan). O
                // item vem em triggerTitle quando presente; resolve o mercado igual.
                val item = result.triggerTitle?.takeIf { it.isNotBlank() }?.trim()
                if (item != null) {
                    resolveShoppingItems(listOf(item))
                } else {
                    speakTyped(OverlayPersona.addToListWhat, TtsTone.QUESTION)
                    endVoice()
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
                    conversationState.armAwaitingName()
                    showToast("Qual é o nome do ambiente?")
                    speak(OverlayPersona.askEnvironmentName)
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
                    // BUG 1 — não cria imediatamente: passa pela resolução de
                    // localização (paridade com a Home), que confirma o GPS antes.
                    resolveEnvironmentLocation(envName)
                }
            }
            "delete_environment" -> {
                val envName = result.environment ?: ""
                if (envName.isNotEmpty()) {
                    // Fase 1 — pergunta por voz antes de excluir (ação irreversível)
                    startDestructiveConfirm("delete_environment", envName, null,
                        DeleteEnvironmentSkill.question(envName))
                } else {
                    speak(OverlayPersona.askWhichEnvironmentToRemove)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                }
            }
            "delete_trigger" -> {
                val envName = result.environment ?: ""
                val title   = result.triggerTitle
                if (envName.isEmpty()) {
                    // Sem ambiente não há como localizar o lembrete com segurança
                    speak(OverlayPersona.askWhichEnvironmentToRemoveReminder)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                } else {
                    // Fase 1 — confirma por voz. Título nulo/vazio = remover todos do ambiente.
                    startDestructiveConfirm("delete_trigger", envName, title,
                        DeleteTriggerSkill.question(envName, title, title.isNullOrEmpty()))
                }
            }
            // Fase 1 — remover todos os gatilhos de um ambiente (confirmado por voz)
            "delete_all_triggers" -> {
                val envName = result.environment ?: ""
                if (envName.isEmpty()) {
                    speak(OverlayPersona.askWhichEnvironmentToRemoveReminders)
                    CorrelationManager.endOperation("voice")
                    voiceCorrelationId = null
                } else {
                    startDestructiveConfirm("delete_all_triggers", envName, null,
                        DeleteAllTriggersSkill.question(envName))
                }
            }
            // Fase 1 — remover TODOS os ambientes (operação global, confirmada por voz)
            "delete_all_environments" -> {
                startDestructiveConfirm("delete_all_environments", "", null,
                    DeleteAllEnvironmentsSkill.question())
            }
            else -> {
                // Fase 1 — fala real mas intenção não reconhecida: resposta natural.
                speak(OverlayPersona.commandNotUnderstood)
                CorrelationManager.endOperation("voice")
                voiceCorrelationId = null
            }
        }
        } catch (e: Exception) { logException("command_dispatch", e) }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Fase 2.2 — CONTRATO ÚNICO DE PLANO (paridade total com a Home)
    //
    // Todo este bloco é NOVO. Objetivo da sprint: Home e Overlay produzem EXATAMENTE
    // o mesmo resultado a partir do mesmo schema {"transcricao","reply","actions[]",
    // "follow_up_question","context_updates"}. O parser:
    //   - NUNCA usa indexOf('{')/lastIndexOf('}') cru (REGRA 1) — varre chaves
    //     respeitando aspas/escapes (extractJsonObject);
    //   - IGNORA campos não usados (reply/context/metadata/confidence futuros) —
    //     só actions[].type + params são obrigatórios para executar (REGRA "schema");
    //   - loga a resposta bruta completa em falha (gemini_raw_response, REGRA 3);
    //   - aplica prioridade destrutiva (REGRA 6/7) antes de executar;
    //   - fala com prosódia por tipo de frase (REGRA 8).
    // ═════════════════════════════════════════════════════════════════════════

    // Uma ação do plano — espelha VoiceAction do Dart. Guarda o JSON cru da ação;
    // o executor lê só o que precisa (type + params). Campos extras são ignorados.
    internal data class PlanAction(val type: String, val obj: JSONObject) {
        // Leitura tolerante de string dentre chaves alternativas (name/environment...).
        fun str(vararg keys: String): String? {
            for (k in keys) {
                val v = obj.optString(k, "")
                if (v.isNotBlank() && v.lowercase() != "null") return v.trim()
            }
            return null
        }
    }

    // Resultado do parse do plano. error != null = JSON ausente/truncado/inválido.
    internal data class PlanResult(
        val actions:    List<PlanAction>,
        val transcript: String,
        val reply:      String,
        val followUp:   String?,
        val error:      String? = null,
    )

    // Tom da fala — deriva a prosódia (REGRA 8). Android TTS usa a pontuação para
    // entonação; garantimos '?' em perguntas e ajustamos pitch/rate por tom.
    private enum class TtsTone { QUESTION, CONFIRM, SUCCESS, ERROR, INFO }

    // Extrai o PRIMEIRO objeto JSON balanceado de [s] respeitando aspas e escapes.
    // REGRA 1: não faz `{`..`}` ingênuo — conta chaves só FORA de strings, então um
    // '}' dentro de um valor textual não encerra o objeto. Retorna null se o objeto
    // não fecha (resposta truncada) — o chamador trata como erro real, sem mascarar.
    private fun extractJsonObject(s: String): String? {
        val start = s.indexOf('{')
        if (start < 0) return null
        var depth = 0; var inStr = false; var esc = false
        for (i in start until s.length) {
            val c = s[i]
            if (inStr) {
                if (esc) esc = false
                else if (c == '\\') esc = true
                else if (c == '"') inStr = false
            } else {
                when (c) {
                    '"'  -> inStr = true
                    '{'  -> depth++
                    '}'  -> { depth--; if (depth == 0) return s.substring(start, i + 1) }
                }
            }
        }
        return null
    }

    // Parseia o envelope do Gemini → PlanResult. Robusto: extrai o texto do candidate,
    // remove cercas markdown e localiza o objeto JSON balanceado. Nunca lança — falhas
    // viram PlanResult(error=...) para tratamento natural.
    private fun parsePlanResponse(raw: String): PlanResult {
        val corrId = CorrelationManager.correlationIdFor("voice")
        Logger.debug("overlay_parser_started", feature = "floating_voice", action = "parse",
            correlationId = corrId) // LOG TEMPORÁRIO (Fase 2.2) — remover após validar
        return try {
            val text = JSONObject(raw)
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts").getJSONObject(0)
                .getString("text")
            val stripped = text
                .replace(Regex("```[a-zA-Z]*\\n?"), "").replace("```", "").trim()

            val jsonStr = extractJsonObject(stripped)
            if (jsonStr == null) {
                // Sem objeto fechado = truncado/ausente. LOG TEMPORÁRIO com a resposta
                // COMPLETA (não só a exceção) para diagnóstico definitivo (REGRA 3).
                Logger.warn("gemini_raw_response", feature = "floating_voice", action = "parse",
                    payload = mapOf("raw" to stripped), correlationId = corrId)
                return PlanResult(emptyList(), "", "", null, error = "json_not_found_or_truncated")
            }

            val obj        = JSONObject(jsonStr)
            val transcript = obj.optString("transcricao", obj.optString("transcript", ""))
            val reply      = obj.optString("reply", "")
            val followUp   = obj.optString("follow_up_question")
                .takeIf { it.isNotBlank() && it.lowercase() != "null" }

            val actions = mutableListOf<PlanAction>()
            val arr = obj.optJSONArray("actions")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val a = arr.optJSONObject(i) ?: continue
                    val t = a.optString("type").takeIf { it.isNotEmpty() } ?: continue
                    actions.add(PlanAction(t, a))
                }
            } else if (obj.has("intent")) {
                // Compat (REGRA 10): schema antigo single-intent → 1 ação equivalente.
                legacyIntentToAction(obj)?.let { actions.add(it) }
            }

            Logger.debug("overlay_parser_finished", feature = "floating_voice", action = "parse",
                payload = mapOf("action_count" to actions.size.toString()),
                correlationId = corrId) // LOG TEMPORÁRIO (Fase 2.2)
            PlanResult(actions, transcript, reply, followUp)
        } catch (e: Exception) {
            Logger.error("overlay_parser_error", feature = "floating_voice", action = "parse",
                exception = e, payload = mapOf("raw" to raw.take(1000)),
                correlationId = corrId) // LOG TEMPORÁRIO (Fase 2.2)
            logException("plan_parser", e)
            PlanResult(emptyList(), "", "", null, error = "parse_error: ${e.message}")
        }
    }

    // Compat: converte o schema antigo {"intent":...} em uma PlanAction equivalente,
    // para que respostas legadas continuem funcionando pelo mesmo executor (REGRA 10).
    private fun legacyIntentToAction(o: JSONObject): PlanAction? {
        val intent = o.optString("intent", "unknown")
        val a = JSONObject()
        when (intent) {
            "create_trigger" -> {
                a.put("type", "create_trigger")
                a.put("environment", o.optString("environment"))
                a.put("title", o.optJSONObject("trigger")?.optString("title") ?: "")
                a.put("content", o.optJSONObject("trigger")?.optString("content") ?: "")
            }
            "create_environment" -> {
                a.put("type", "create_environment")
                a.put("name", o.optJSONObject("environment")?.optString("name")
                    ?: o.optString("environment"))
            }
            "delete_environment"      -> { a.put("type", "delete_environment"); a.put("environment", o.optString("environment")) }
            "delete_trigger"          -> { a.put("type", "delete_trigger"); a.put("environment", o.optString("environment")); a.put("title", o.optString("title")) }
            "delete_all_triggers"     -> { a.put("type", "delete_all_triggers"); a.put("environment", o.optString("environment")) }
            "delete_all_environments" -> a.put("type", "delete_all_environments")
            else                      -> return null
        }
        return PlanAction(a.optString("type"), a)
    }

    // Guarda de PRIORIDADE DESTRUTIVA (REGRA 6/7). Roda sobre a TRANSCRIÇÃO, não sobre
    // a classificação do Gemini: se a fala pede exclusão TOTAL de ambientes, nenhuma
    // ação de criação pode vencer — força [delete_all_environments]. Corrige o BUG 2
    // ("apagar todos os ambientes" virava createTrigger). Exclusão de lembretes de um
    // local (com palavra gatilho/lembrete) é deixada ao plano do Gemini, que carrega
    // o ambiente correto.
    private fun applyDestructivePriority(plan: PlanResult): PlanResult {
        val t = plan.transcript.lowercase(Locale("pt", "BR"))
        val verb    = listOf("apag", "remov", "exclu", "delet", "limp").any { t.contains(it) }
        if (!verb) return plan
        val total   = listOf("todos", "todas", "tudo").any { t.contains(it) }
        val trgWord = listOf("gatilho", "lembrete", "lembranca", "lembrança").any { t.contains(it) }
        // "apagar todos os ambientes", "excluir todos", "remover tudo", "limpar todos",
        // "deletar tudo" — total SEM palavra de gatilho → wipe de ambientes.
        if (total && !trgWord) {
            Logger.info("intent_priority_applied", feature = "floating_voice", action = "priority",
                payload = mapOf("forced" to "delete_all_environments"),
                correlationId = voiceCorrelationId) // LOG TEMPORÁRIO (Fase 2.2)
            val a = JSONObject().put("type", "delete_all_environments")
            return plan.copy(actions = listOf(PlanAction("delete_all_environments", a)))
        }
        return plan
    }

    // Interpreta o PLANO vindo do Gemini (HTTP 200). Roda na Main thread.
    // Ordem: parse robusto → estados de espera (compat) → prioridade → executar.
    private fun handleGeminiPlan(raw: String) {
        val parsed = parsePlanResponse(raw)

        // Falha real de parse (truncado/inválido). NÃO mascara: fala natural + encerra.
        if (parsed.error != null) {
            Logger.warn("voice_result_error", feature = "floating_voice", action = "execute",
                payload = mapOf("error" to parsed.error), correlationId = voiceCorrelationId)
            speakTyped(OverlayPersona.notUnderstoodRepeat, TtsTone.ERROR)
            CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            return
        }

        // Estados de espera (nome de ambiente / confirmação sim-não / etc.) continuam
        // sendo resolvidos pelo fluxo legado, que só precisa da transcrição (REGRA 10).
        if (hasActiveAwaitingState()) {
            executeVoiceResult(FloatVoiceResult(
                intent = null, environment = null, triggerTitle = null,
                triggerContent = null, transcript = parsed.transcript))
            return
        }

        // REGRA 4 / BUG 3 — 2ª PROTEÇÃO: NUNCA executa plano com transcrição
        // inválida (vazia, só espaços, "...", "00:00", só pontuação), mesmo que o
        // Gemini tenha alucinado ações. Dupla proteção: gate de energia (antes do
        // Gemini) + esta validação (antes do ExecutionPlan).
        if (isInvalidTranscript(parsed.transcript)) {
            Logger.warn("execution_plan_blocked", feature = "floating_voice", action = "execute",
                payload = mapOf("surface" to "overlay", "reason" to "invalid_transcript"),
                correlationId = voiceCorrelationId)
            Logger.warn("execution_plan_invalid_transcript", feature = "floating_voice",
                action = "execute", payload = mapOf("surface" to "overlay",
                    "transcript" to parsed.transcript),
                correlationId = voiceCorrelationId)
            speakTyped(OverlayPersona.notHeard, TtsTone.ERROR) // REGRA 3
            endVoice()
            return
        }

        val plan = applyDestructivePriority(parsed)
        // LOG TEMPORÁRIO (BUG 1) — início da execução do plano no Overlay.
        Logger.info("overlay_execution_started", feature = "floating_voice", action = "execute",
            payload = mapOf("surface" to "overlay", "actions" to plan.actions.size.toString()),
            correlationId = voiceCorrelationId)
        executePlan(plan)
    }

    // True se há um estado de espera de voz ativo e não expirado (30 s). Espelha a
    // checagem de executeVoiceResult para decidir entre "resposta a pergunta" x "novo".
    private fun hasActiveAwaitingState(): Boolean {
        val state = conversationState.current ?: return false
        return !conversationState.isExpired && state.isNotEmpty()
    }

    // Executa o plano em sequência (paridade com VoiceActionExecutor.run da Home):
    //   - qualquer ação destrutiva → UMA confirmação por voz (reusa o fluxo Fase 1);
    //   - senão → resolve GPS uma vez (se cria ambiente) e roda as ações em ordem,
    //     tolerando falhas isoladas; fala o reply (ou um resumo natural) ao final.
    private fun executePlan(plan: PlanResult) {
        // Estágio 4 — decisão de roteamento isolada no Planner (mesma ordem/condições).
        val route = OverlayPlanner.routePlan(plan) { BLOCKED_ENV_NAMES.contains(it.lowercase()) }

        // Sem ações: só conversa. Pergunta (follow_up) tem prosódia interrogativa.
        if (route is PlanRoute.Empty) {
            when {
                plan.followUp != null      -> speakTyped(plan.followUp, TtsTone.QUESTION)
                plan.reply.isNotBlank()    -> speakTyped(plan.reply, TtsTone.INFO)
                else                       -> speakTyped(OverlayPersona.notUnderstoodRepeat, TtsTone.ERROR)
            }
            CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            return
        }

        // Destrutivo: confirma a PRIMEIRA ação destrutiva (a prioridade já colapsou o
        // wipe total em uma única ação). A confirmação reusa startDestructiveConfirm.
        if (route is PlanRoute.Destructive) {
            routeDestructiveConfirm(route.action)
            return
        }

        // Lista de compras: plano composto SÓ de add_shopping_item é resolvido à
        // parte (não usa o loop construtivo/GPS nem o resumo genérico). Junta todos
        // os itens e resolve o mercado uma única vez — pergunta "qual mercado?" só
        // quando houver 2+. Evita o conflito de TTS com o resumo do loop.
        if (route is PlanRoute.Shopping) {
            val items = plan.actions
                .mapNotNull { it.str("item", "name", "title") }
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (items.isEmpty()) {
                speakTyped(OverlayPersona.itemNotUnderstood, TtsTone.ERROR)
                endVoice()
            } else {
                resolveShoppingItems(items)
            }
            return
        }

        // Clima: consulta que FALA o tempo (não muta o banco). Rota própria — o
        // texto vem do OverlayWeather (paridade com a fala de clima do Home).
        if (route is PlanRoute.Weather) {
            handleWeatherQuery(route.action)
            return
        }

        // Resolução Inteligente de Localização — plano que APENAS cria um ambiente
        // (sem gatilhos/outras ações) não usa GPS cego: confirma a localização
        // antes (paridade com a Home). Planos mistos seguem o fluxo GPS atual.
        if (route is PlanRoute.SingleEnvironment) {
            resolveEnvironmentLocation(route.name)
            return
        }

        // Construtivo: create_environment / create_trigger em ordem, GPS uma única vez.
        val needsLoc = plan.actions.any { it.type == "create_environment" }
        showProcessingState()
        // LOGS TEMPORÁRIOS (BUG 6/7) — início do plano + executor nomeado do Overlay.
        Logger.info("execution_plan_started", feature = "floating_voice", action = "execute",
            payload = mapOf("surface" to "overlay", "actions" to plan.actions.size.toString()),
            correlationId = voiceCorrelationId)
        Logger.info("overlay_executor_started", feature = "floating_voice", action = "execute",
            payload = mapOf("surface" to "overlay"), correlationId = voiceCorrelationId)
        val execStart = System.currentTimeMillis() // BUG 4 (temporário)
        serviceScope.launch(Dispatchers.IO) {
            val loc = if (needsLoc) getLastLocationBlocking() else null
            val lat = loc?.latitude ?: 0.0
            val lon = loc?.longitude ?: 0.0
            var ok = 0; var fail = 0
            for (a in plan.actions) {
                // Estágio 2 — construção delegada às Skills (mesmo corpo síncrono).
                val done = when (a.type) {
                    "create_environment" ->
                        CreateEnvironmentSkill.execute(a.str("name", "environment"), lat, lon, skillContext)
                    "create_trigger" ->
                        CreateTriggerSkill.execute(a.str("environment", "name"), a.str("title"),
                            a.str("content") ?: "", skillContext)
                    // Etapa 2 — paridade com o Home (mesma semântica das Skills Dart).
                    "update_trigger" ->
                        UpdateTriggerSkill.execute(a.str("environment", "name"), a.str("title"),
                            a.str("new_title"), a.str("content"), skillContext)
                    "update_environment" ->
                        UpdateEnvironmentSkill.execute(a.str("name", "environment"),
                            a.str("radius")?.toIntOrNull(), skillContext)
                    "create_reminder" ->
                        CreateReminderSkill.execute(a, skillContext)
                    else -> false // tipos não suportados no overlay (ex.: weather na rota própria)
                }
                if (done) ok++ else fail++
            }
            // Sinaliza a UI para atualizar ao voltar ao foreground (mesmos providers).
            if (ok > 0) getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis())
                .apply()

            val execMs = System.currentTimeMillis() - execStart // BUG 4 (temporário)
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                Logger.info("plan_executed", feature = "floating_voice", action = "execute",
                    payload = mapOf("ok" to ok.toString(), "fail" to fail.toString()),
                    correlationId = voiceCorrelationId)
                // LOGS TEMPORÁRIOS (BUG 6) — fim/falha do plano com surface/actions/ok/failed/duration_ms.
                if (ok == 0 && fail > 0) {
                    Logger.warn("execution_plan_failed", feature = "floating_voice", action = "execute",
                        payload = mapOf("surface" to "overlay",
                            "actions" to plan.actions.size.toString(), "failed" to fail.toString()),
                        correlationId = voiceCorrelationId)
                }
                Logger.info("execution_plan_finished", feature = "floating_voice", action = "execute",
                    payload = mapOf("surface" to "overlay",
                        "actions" to plan.actions.size.toString(),
                        "ok" to ok.toString(), "failed" to fail.toString(),
                        "duration_ms" to execMs.toString()),
                    correlationId = voiceCorrelationId)
                // LOGS TEMPORÁRIOS (BUG 1/7) — executor/execução/pipeline nomeados do Overlay.
                Logger.info("overlay_executor_finished", feature = "floating_voice", action = "execute",
                    payload = mapOf("surface" to "overlay"), correlationId = voiceCorrelationId)
                Logger.info("overlay_execution_finished", feature = "floating_voice", action = "execute",
                    payload = mapOf("surface" to "overlay", "duration_ms" to execMs.toString()),
                    correlationId = voiceCorrelationId)
                Logger.info("overlay_pipeline_finished", feature = "floating_voice", action = "execute",
                    payload = mapOf("surface" to "overlay"), correlationId = voiceCorrelationId)
                when {
                    ok == 0 && fail > 0        -> speakTyped(OverlayPersona.couldNotFinishRetry, TtsTone.ERROR)
                    fail > 0                   -> speakTyped(OverlayPersona.partialFailure(fail), TtsTone.INFO)
                    plan.reply.isNotBlank()    -> speakTyped(plan.reply, TtsTone.SUCCESS)
                    else                       -> speakTyped(OverlayPersona.done, TtsTone.SUCCESS)
                }
                CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            }
        }
    }

    // Consulta de clima (Etapa 2) — resolve o local, consulta a OWM nativamente e
    // FALA o tempo (o texto vem do OverlayWeather). GPS via getLastLocationBlocking,
    // mesmo pipeline das outras rotas.
    private fun handleWeatherQuery(a: PlanAction) {
        showProcessingState()
        val place = a.str("location", "city", "place")
        val scope = (a.str("scope") ?: "now").lowercase()
        serviceScope.launch(Dispatchers.IO) {
            val spoken = OverlayWeather.answer(
                this@FloatingVoiceService, place, scope) { getLastLocationBlocking() }
            withContext(Dispatchers.Main) {
                revertButtonAppearance()
                speakTyped(spoken, TtsTone.INFO)
                CorrelationManager.endOperation("voice"); voiceCorrelationId = null
            }
        }
    }

    // Mapeia uma ação destrutiva → pergunta de confirmação por voz (reusa Fase 1).
    // A pergunta sempre termina com '?' e é falada com entonação interrogativa.
    private fun routeDestructiveConfirm(a: PlanAction) {
        // Estágio 2 — a STRING de confirmação vem da Skill (fonte única). Os prompts
        // de ambiente-faltando ficam aqui (prosódia própria deste pipeline de plano).
        when (a.type) {
            "delete_all_environments" ->
                startDestructiveConfirm("delete_all_environments", "", null,
                    DeleteAllEnvironmentsSkill.question())
            "delete_all_triggers" -> {
                val env = a.str("environment", "name")
                if (env == null) { speakTyped(OverlayPersona.askWhichEnvironmentToRemoveReminders, TtsTone.QUESTION); endVoice() }
                else startDestructiveConfirm("delete_all_triggers", env, null,
                    DeleteAllTriggersSkill.question(env))
            }
            "delete_environment" -> {
                val env = a.str("environment", "name")
                if (env == null) { speakTyped(OverlayPersona.askWhichEnvironmentToRemove, TtsTone.QUESTION); endVoice() }
                else startDestructiveConfirm("delete_environment", env, null,
                    DeleteEnvironmentSkill.question(env))
            }
            "delete_trigger" -> {
                val env   = a.str("environment", "name")
                val title = a.str("title")
                if (env == null) { speakTyped(OverlayPersona.askWhichEnvironmentToRemoveReminder, TtsTone.QUESTION); endVoice() }
                else startDestructiveConfirm("delete_trigger", env, title,
                    DeleteTriggerSkill.question(env, title, title == null))
            }
            else -> endVoice()
        }
    }

    // Encerra o ciclo de voz atual (helper de legibilidade).
    private fun endVoice() { CorrelationManager.endOperation("voice"); voiceCorrelationId = null }

    // Fala com prosódia por tipo (REGRA 8). Reusa speak() (grava floating_spoke_at
    // para a Home não duplicar o TTS). Perguntas ganham '?' e pitch mais alto.
    private fun speakTyped(text: String, tone: TtsTone) {
        val engine = tts
        if (engine != null) {
            when (tone) {
                TtsTone.QUESTION -> { engine.setPitch(1.12f); engine.setSpeechRate(0.94f) }
                TtsTone.CONFIRM  -> { engine.setPitch(1.05f); engine.setSpeechRate(0.95f) }
                TtsTone.SUCCESS  -> { engine.setPitch(1.08f); engine.setSpeechRate(0.98f) }
                TtsTone.ERROR    -> { engine.setPitch(1.00f); engine.setSpeechRate(0.95f) }
                TtsTone.INFO     -> { engine.setPitch(1.05f); engine.setSpeechRate(0.95f) }
            }
        }
        val phrase = if (tone == TtsTone.QUESTION && !text.trimEnd().endsWith("?")) "$text?" else text
        Logger.debug("tts_phrase_type", feature = "floating_voice", action = "tts",
            payload = mapOf("tone" to tone.name),
            correlationId = voiceCorrelationId) // LOG TEMPORÁRIO (Fase 2.2)
        speak(phrase)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fase 1 — guardas, confirmação por voz e exclusão global
    // ─────────────────────────────────────────────────────────────────────────

    // true se a transcrição não representa fala real: vazia, padrão de relógio
    // ("00:00", "0:00", "00.00") ou apenas pontuação (sem letra/dígito).
    // Usada em onResults para encerrar sem chamar o Gemini e sem popup.
    private fun isInvalidTranscript(text: String?): Boolean {
        if (text == null) return true
        val t = text.trim()
        if (t.isEmpty()) return true
        if (CLOCK_LIKE_REGEX.matches(t)) return true
        if (!WORD_CHAR_REGEX.containsMatchIn(t)) return true // só pontuação
        return false
    }

    // Interpreta resposta de confirmação: true=sim, false=não, null=ambíguo.
    // 100% local (sem Gemini). Negativo tem prioridade sobre positivo.
    private fun parseYesNo(text: String): Boolean? {
        val t = text.lowercase(java.util.Locale("pt", "BR")).trim()
        if (NO_WORDS.any { t.contains(it) })  return false
        if (YES_WORDS.any { t.contains(it) }) return true
        return null
    }

    // Reconhece frases de DESISTÊNCIA em qualquer estado de espera ("cancela",
    // "pode encerrar", "esquece isso", "deixa pra lá", "para", "sair"...). Rodada
    // ANTES de parseYesNo/tratar-como-nome para o usuário sempre poder abortar.
    // Espelha _isCancelPhrase do Home (home_tab_content.dart). 100% local.
    private fun isCancelPhrase(text: String): Boolean {
        val t = text.lowercase(java.util.Locale("pt", "BR")).trim()
        if (t.isEmpty()) return false
        // Frases distintivas — casam em qualquer posição (não ocorrem em nomes de
        // lugar reais, então são seguras via contains).
        val strong = listOf(
            "cancel",                        // cancela, cancelar, cancelado
            "encerr",                        // pode encerrar, encerra
            "esquec",                        // esquece isso, esquecer
            "desist",                        // desisto, desistir
            "deixa pra", "deixa para",       // deixa pra lá
            "deixa quieto", "deixa isso",
            "sai dessa",
            "nao quero mais", "não quero mais",
        )
        if (strong.any { t.contains(it) }) return true
        // Comandos curtos e ambíguos ("para", "sair") — só valem se forem a fala
        // INTEIRA (poucas palavras), evitando falso positivo em nomes ("Paraná").
        val words = t.split(Regex("\\s+"))
        return words.size <= 3 &&
            Regex("\\b(para|parar|pare|parou|sair|sai)\\b").containsMatchIn(t)
    }

    // Sprint F3-3 — cria o ambiente por voz SEM GPS cego. Nomes pessoais
    // (casa/lar/trabalho/escritório/serviço) tentam a localização atual; se o GPS
    // estiver disponível, criam COM coords + geofence. Todos os demais (e os
    // pessoais sem GPS) nascem SEM coords: o endereço é definido depois na
    // AddEnvironmentScreen, aberta via pending nas SharedPreferences.
    private fun resolveEnvironmentLocation(name: String) {
        // LOG TEMPORÁRIO — início da resolução de localização.
        Logger.info("location_resolution_started", feature = "floating_voice",
            action = "location", payload = mapOf("name" to name),
            correlationId = voiceCorrelationId)
        val personalNames = listOf("casa", "lar", "trabalho",
            "escritório", "escritorio", "serviço", "servico")
        val isPersonal = personalNames.any { name.lowercase().contains(it) }
        showToast("Criando '$name'...")
        serviceScope.launch(Dispatchers.IO) {
            // Nome pessoal → tenta GPS atual e cria COM coords + geofence.
            if (isPersonal) {
                val loc = getLastLocationBlocking()
                val lat = loc?.latitude ?: 0.0
                val lon = loc?.longitude ?: 0.0
                if (lat != 0.0 && lon != 0.0) {
                    val ok = writeEnvironmentToDb(name, lat, lon, 100)
                    withContext(Dispatchers.Main) {
                        speak(if (ok) OverlayPersona.environmentCreated(name)
                              else OverlayPersona.couldNotCreateNow(name))
                        endVoice()
                    }
                    return@launch
                }
                // Sem GPS → segue para o caminho sem coords + pending.
            }
            // Caso geral (ou pessoal sem GPS): cria SEM coords e deixa pending.
            val envId = writeEnvironmentNoCoordsToDb(name)
            withContext(Dispatchers.Main) {
                if (envId != null) {
                    savePendingLocationEnv(envId, capitalizeEnvName(name))
                    Logger.info("floating_env_created_pending", feature = "floating_voice",
                        action = "db_write",
                        payload = mapOf("env_id" to envId, "env_name" to name,
                            "has_coords" to "false"),
                        correlationId = voiceCorrelationId)
                    // Pessoal sem GPS: confirma só a criação; geral orienta a abrir o app.
                    speak(if (isPersonal) OverlayPersona.environmentCreated(name)
                          else OverlayPersona.environmentCreatedOpenApp(name))
                } else {
                    speak(OverlayPersona.couldNotCreateNow(name))
                }
                endVoice()
            }
        }
    }

    // Capitaliza cada palavra do nome do ambiente em pt-BR (paridade com a Home
    // e com writeEnvironmentToDb). Usado no pending e no insert sem coords.
    private fun capitalizeEnvName(name: String): String =
        name.trim().split(" ").joinToString(" ") { word ->
            word.lowercase(java.util.Locale("pt", "BR"))
                .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
        }

    // Sprint F3-3 — persiste o ambiente pendente de localização. A HomeScreen lê
    // no onResume (sem o prefixo "flutter.", removido pelo plugin Dart) e abre a
    // AddEnvironmentScreen em modo "só localização". needs_refresh mostra o novo
    // ambiente na lista imediatamente.
    private fun savePendingLocationEnv(envId: String, envName: String) {
        getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).edit()
            .putString("flutter.pending_location_env_id", envId)
            .putString("flutter.pending_location_env_name", envName)
            .putBoolean("flutter.needs_refresh", true)
            .putLong("flutter.needs_refresh_at", System.currentTimeMillis())
            .apply()
        // Push: se o app estiver vivo, atualiza a UI na hora (senão, cold start cobre).
        MainActivity.notifyDataChanged()
    }

    // Sprint F3-3 — insere um ambiente SEM coordenadas (lat/lon = 0.0) e SEM
    // geofence. Retorna o UUID criado, ou null em falha. Padrão SQLite obrigatório:
    // db.close() no finally.
    private fun writeEnvironmentNoCoordsToDb(name: String): String? {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null)
        val resolvedPath = dbPath ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs"), correlationId = corrId)
            return null
        }
        val dbFile = File(resolvedPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to resolvedPath), correlationId = corrId)
            return null
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val envNameCapitalized = capitalizeEnvName(name)
            val id  = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            db.execSQL(
                "INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                arrayOf(id, envNameCapitalized, 0.0, 0.0, 100.0, now)
            )
            Logger.info("environment_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("id" to id, "has_coords" to "false"),
                correlationId = corrId)
            id
        } catch (e: Exception) {
            Logger.error("sqlite_write_environment_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start, exception = e,
                correlationId = corrId)
            logException("command_dispatch", e)
            null
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    // Classifica a origem da localização (espelha o LocationSourceResolver da Home).
    // Overlay só resolve GPS localmente: retorna "gps" para local atual/personalizado
    // e "app" para o que exige geocoder (categoria genérica ou endereço possessivo).
    private fun classifyLocationSource(name: String): String {
        val lower = name.trim().lowercase(java.util.Locale("pt", "BR"))
        if (lower.isEmpty()) return "app"
        // Possessivo ("Casa da mãe") → endereço (precisa de geocoder → app).
        if (Regex("""(^|\s)(da|do|de|das|dos)\s""").containsMatchIn(lower)) return "app"
        // Categoria genérica pura ("Mercado", "Farmácia") → NUNCA GPS → app.
        val generic = setOf(
            "mercado", "supermercado", "farmacia", "farmácia", "hospital",
            "academia", "escola", "shopping", "restaurante", "correios", "banco",
            "loja", "posto", "padaria", "lanchonete", "clinica", "clínica",
        )
        if (generic.contains(lower)) return "app"
        // Local atual (residencial) ou nome personalizado → GPS com confirmação.
        return "gps"
    }

    // Pergunta se pode usar a localização atual e arma o estado de espera. A resposta
    // sim/não chega na PRÓXIMA gravação (o usuário segura o botão de novo) — mesmo
    // padrão de startDestructiveConfirm (evita o mic captar o próprio TTS e mantém a
    // máquina de estados TTS → WAITING_USER_RESPONSE → IDLE).
    private fun askLocationConfirm(name: String) {
        conversationState.armLocationConfirm(name)
        // LOGS TEMPORÁRIOS — aguardando resposta do usuário (paridade com a Home).
        Logger.info("location_resolution_waiting", feature = "floating_voice",
            action = "location", payload = mapOf("name" to name, "stage" to "confirm_gps"),
            correlationId = voiceCorrelationId)
        Logger.info("waiting_user_response", feature = "floating_voice", action = "location",
            payload = mapOf("surface" to "overlay", "state" to VAL_AWAITING_LOCATION_CONFIRM),
            correlationId = voiceCorrelationId)
        speakTyped(OverlayPersona.confirmUseCurrentLocation(name), TtsTone.QUESTION)
        showToast("Segure o botão e responda sim ou não.")
        // Encerra o ciclo atual; a resposta abre um novo ciclo ao segurar o botão.
        endVoice()
    }

    // Cria o ambiente na localização atual (GPS) — caminho reutilizado pela resposta
    // "sim" da confirmação; equivale ao create_environment antigo do overlay.
    private fun createEnvironmentWithGps(name: String) {
        showToast("Criando '$name'...")
        serviceScope.launch(Dispatchers.IO) {
            val loc = getLastLocationBlocking()
            val lat = loc?.latitude ?: 0.0
            val lon = loc?.longitude ?: 0.0
            val ok = if (lat != 0.0 && lon != 0.0) writeEnvironmentToDb(name, lat, lon, 100) else false
            // LOG TEMPORÁRIO — fim da resolução de localização.
            Logger.info("location_resolution_finished", feature = "floating_voice",
                action = "location", payload = mapOf("name" to name, "created" to ok.toString()),
                correlationId = voiceCorrelationId)
            withContext(Dispatchers.Main) {
                if (ok) speak(OverlayPersona.environmentCreatedReady(name))
                else speak(OverlayPersona.locationUnavailableManual)
                endVoice()
            }
        }
    }

    // Arma o estado de confirmação por voz e faz a pergunta.
    //
    // Fluxo: grava intent/env/title em SharedPreferences, fala [question] e
    // orienta o usuário a responder. Encerra o ciclo de voz atual — a resposta
    // inicia um NOVO ciclo (o usuário segura o botão de novo). A próxima fala é
    // roteada por onResults para executeVoiceResult como resposta sim/não.
    // Motivo de não auto-escutar: evita o microfone captar o próprio TTS.
    private fun startDestructiveConfirm(
        intent: String, envName: String, title: String?, question: String,
    ) {
        conversationState.armDestructive(intent, envName, title)

        Logger.info("voice_confirmation_started", feature = "floating_voice",
            action = "confirm", payload = mapOf("intent" to intent),
            correlationId = voiceCorrelationId)
        // BUG 3 / REGRA 8 — pergunta de confirmação com entonação interrogativa.
        speakTyped(question, TtsTone.QUESTION)
        showToast("Segure o botão e responda sim ou não.")
        // Encerra o ciclo atual; a resposta abrirá um novo ciclo ao segurar o botão.
        CorrelationManager.endOperation("voice")
        voiceCorrelationId = null
    }

    // Executa a operação destrutiva já confirmada por voz. Sempre em IO thread;
    // fala o resultado na Main. Encerra o ciclo de voz ao final de cada ramo.
    private fun performConfirmedDestructive(intent: String, envName: String, title: String?) {
        // Estágio 2 — execução delegada às Skills (mesmo corpo IO→DB→log→fala→fim).
        when (intent) {
            "delete_environment"      -> DeleteEnvironmentSkill.perform(envName, skillContext)
            // Título nulo → remover todos do ambiente; senão, remover o específico
            "delete_trigger"          -> DeleteTriggerSkill.perform(envName, title, skillContext)
            "delete_all_triggers"     -> DeleteAllTriggersSkill.perform(envName, skillContext)
            "delete_all_environments" -> DeleteAllEnvironmentsSkill.perform(skillContext)
            else -> { CorrelationManager.endOperation("voice"); voiceCorrelationId = null }
        }
    }

    // Remove TODOS os ambientes e gatilhos do banco. Retorna a quantidade de
    // ambientes removidos (0 em erro ou banco vazio). Chamado de Dispatchers.IO.
    // Também limpa geofences nativos e o mapa de nomes do GeofenceReceiver, e
    // sinaliza needs_refresh para o app atualizar a UI ao voltar ao foreground.
    private fun deleteAllEnvironmentsFromDb(): Int {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "delete_all_envs"),
                correlationId = corrId)
            return 0
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "delete_all_envs"),
                correlationId = corrId)
            return 0
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            // Coleta os ids ANTES de apagar — necessários para remover geofences
            val ids = mutableListOf<String>()
            db.rawQuery("SELECT id FROM environments", null).use { c ->
                while (c.moveToNext()) ids.add(c.getString(0))
            }
            // Apaga gatilhos primeiro (FK), depois os ambientes
            db.execSQL("DELETE FROM triggers")
            db.execSQL("DELETE FROM environments")
            // Geofences exigem main thread; mapa de nomes do receiver é limpo aqui
            if (ids.isNotEmpty()) mainHandler.post { removeGeofences(ids) }
            getSharedPreferences(GeofenceReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                .edit().clear().apply()
            getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis())
                .apply()
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, cold start cobre).
            MainActivity.notifyDataChanged()
            Logger.info("all_environments_deleted", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("count" to ids.size.toString()),
                correlationId = corrId)
            ids.size
        } catch (e: Exception) {
            Logger.error("sqlite_delete_all_environments_failed", feature = "floating_voice",
                action = "db_write", durationMs = System.currentTimeMillis() - start,
                exception = e, correlationId = corrId)
            logException("command_dispatch", e)
            0
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Remove uma lista de geofences nativos de uma vez (best-effort). Main thread.
    private fun removeGeofences(ids: List<String>) {
        try {
            LocationServices.getGeofencingClient(this).removeGeofences(ids)
                .addOnSuccessListener {
                    Logger.debug("geofences_removed", feature = "floating_voice",
                        action = "geofence", payload = mapOf("count" to ids.size.toString()))
                }
                .addOnFailureListener { e -> logException("geofence_remove", e) }
        } catch (e: Exception) {
            logException("geofence_remove", e)
        }
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
    // Lista de compras (mercados) — caminho nativo do overlay
    // ─────────────────────────────────────────────────────────────────────────

    // Lê (id, name) de todos os ambientes com is_market = 1. Read-only + finally
    // close, mesmo padrão de readEnvironmentNamesFromDb. Chamado de Dispatchers.IO.
    private fun queryMarketEnvironments(): List<Pair<String, String>> {
        val dbFile = findDbFile() ?: return emptyList()
        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
            val cursor = db.rawQuery(
                "SELECT id, name FROM environments WHERE is_market = 1", null
            )
            val out = mutableListOf<Pair<String, String>>()
            cursor.use { while (it.moveToNext()) out.add(it.getString(0) to it.getString(1)) }
            out
        } catch (e: Exception) {
            Logger.warn("sqlite_read_markets_failed", feature = "floating_voice", action = "db_read",
                exception = e, correlationId = CorrelationManager.correlationIdFor("voice"))
            emptyList()
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Insere N itens na lista de compras do mercado [marketName] (busca o id por
    // nome, exige is_market = 1). Espelha writeTriggerToDb (READWRITE + finally).
    // Retorna true se o mercado existe e os inserts ocorreram.
    private fun writeShoppingItemsToDb(items: List<String>, marketName: String): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("op" to "write_shopping"), correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) return false
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val cursor = db.rawQuery(
                "SELECT id FROM environments WHERE LOWER(name) = LOWER(?) AND is_market = 1 LIMIT 1",
                arrayOf(marketName)
            )
            val envId = if (cursor.moveToFirst()) cursor.getString(0) else null
            cursor.close()
            if (envId == null) {
                Logger.warn("market_not_found", feature = "floating_voice", action = "db_write",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("market_name" to marketName) else null,
                    correlationId = corrId)
                return false
            }
            val now = System.currentTimeMillis()
            for (raw in items) {
                val name = capitalizePt(raw)
                val id = UUID.randomUUID().toString()
                db.execSQL(
                    "INSERT INTO shopping_list_items (id, environment_id, name, is_checked, created_at) " +
                    "VALUES (?, ?, ?, 0, ?)",
                    arrayOf(id, envId, name, now)
                )
            }
            // Sinaliza a UI para atualizar ao voltar ao foreground (mesmos providers).
            getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis())
                .apply()
            Logger.info("shopping_items_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = mapOf("count" to items.size.toString(), "market" to marketName),
                correlationId = corrId)
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, needs_refresh cobre).
            MainActivity.notifyDataChanged()
            true
        } catch (e: Exception) {
            Logger.error("sqlite_write_shopping_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start, exception = e,
                correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Resolve em qual mercado gravar os [items]: 0 → orienta criar; 1 → grava direto
    // e confirma; 2+ → arma VAL_AWAITING_MARKET_CHOICE e pergunta por voz qual mercado.
    private fun resolveShoppingItems(items: List<String>) {
        showProcessingState()
        serviceScope.launch(Dispatchers.IO) {
            val markets = queryMarketEnvironments()
            withContext(Dispatchers.Main) {
                when {
                    markets.isEmpty() -> {
                        revertButtonAppearance()
                        speakTyped(OverlayPersona.noMarketYet, TtsTone.QUESTION)
                        endVoice()
                    }
                    markets.size == 1 -> {
                        val market = markets.first().second
                        serviceScope.launch(Dispatchers.IO) {
                            val ok = AddShoppingItemSkill.execute(items, market, skillContext)
                            withContext(Dispatchers.Main) {
                                revertButtonAppearance()
                                if (ok) speakTyped(confirmShoppingPhrase(items, market), TtsTone.SUCCESS)
                                else speakTyped(OverlayPersona.couldNotSaveNow, TtsTone.ERROR)
                                endVoice()
                            }
                        }
                    }
                    else -> {
                        revertButtonAppearance()
                        val names = markets.map { it.second }
                        conversationState.armMarketChoice(
                            items.joinToString("|"), names.joinToString("|"))
                        speakTyped(
                            OverlayPersona.whichMarket(humanJoin(names), humanJoin(items)),
                            TtsTone.QUESTION)
                        showToast("Segure o botão e diga o nome do mercado.")
                        endVoice()
                    }
                }
            }
        }
    }

    // Casa a fala do usuário contra os nomes dos mercados. Tenta (a) nome contido
    // (sem acento/caixa) e (b) ordinal falado. Retorna o índice OU null (nenhum/ambíguo).
    private fun parseMarketChoice(transcript: String, marketNames: List<String>): Int? {
        if (marketNames.isEmpty()) return null
        val t = stripAccents(transcript.lowercase(java.util.Locale("pt", "BR")))
        // (a) nome do mercado contido na fala
        val nameMatches = marketNames.indices.filter { i ->
            val n = stripAccents(marketNames[i].lowercase(java.util.Locale("pt", "BR")))
            n.isNotEmpty() && t.contains(n)
        }
        if (nameMatches.size == 1) return nameMatches[0]
        if (nameMatches.size > 1) return null // ambíguo
        // (a2) fallback: última palavra significativa do nome (ex.: "Delta" de
        // "Mercado Delta"). Só quando o nome completo não bateu (0 acima). Ignora
        // a genérica inicial (mercado/supermercado) quando há mais palavras.
        if (nameMatches.isEmpty()) {
            val generic = setOf("mercado", "supermercado")
            val lastWordMatches = marketNames.indices.filter { i ->
                val tokens = stripAccents(marketNames[i].lowercase(java.util.Locale("pt", "BR")))
                    .split(" ").filter { it.isNotBlank() }
                val meaningful =
                    if (tokens.size > 1 && tokens.first() in generic) tokens.drop(1) else tokens
                val last = meaningful.lastOrNull() ?: ""
                last.isNotEmpty() && t.contains(last)
            }
            if (lastWordMatches.size == 1) return lastWordMatches[0]
        }
        // (b) ordinal falado
        val ordinal = when {
            Regex("\\bprimeir").containsMatchIn(t) || Regex("\\bum\\b").containsMatchIn(t) -> 0
            Regex("\\bsegund").containsMatchIn(t) || Regex("\\bdois\\b").containsMatchIn(t) -> 1
            Regex("\\bterceir").containsMatchIn(t) || Regex("\\btres\\b").containsMatchIn(t) -> 2
            Regex("\\bultim").containsMatchIn(t) -> marketNames.lastIndex
            else -> -1
        }
        return if (ordinal in marketNames.indices) ordinal else null
    }

    // "Anotado — Leite e Pão na lista do Assaí." (1 item: sem o "e").
    private fun confirmShoppingPhrase(items: List<String>, market: String): String =
        "Anotado — ${humanJoin(items)} na lista do $market."

    // Junta uma lista para fala natural: "A", "A e B", "A, B e C".
    private fun humanJoin(list: List<String>): String = when (list.size) {
        0 -> ""
        1 -> list[0]
        2 -> "${list[0]} e ${list[1]}"
        else -> "${list.dropLast(1).joinToString(", ")} e ${list.last()}"
    }

    // Capitaliza cada palavra em pt-BR (mesma regra usada em writeEnvironmentToDb).
    private fun capitalizePt(s: String): String = s.trim().split(" ").joinToString(" ") { w ->
        w.lowercase(java.util.Locale("pt", "BR"))
            .replaceFirstChar { it.titlecase(java.util.Locale("pt", "BR")) }
    }

    // Remove acentos para comparação tolerante (NFD + remove marcas diacríticas).
    private fun stripAccents(s: String): String =
        java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")

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
            // TEMP: remover após calibração da resolução de localização
            Logger.info("environment_location_assigned", feature = "floating_voice", action = "db_write",
                payload = mapOf("environment" to envNameCapitalized, "lat" to lat.toString(),
                    "lng" to lon.toString(), "radius" to radius.toString()),
                correlationId = corrId)
            // GMS addGeofences exige main thread
            mainHandler.post { registerGeofence(id, envNameCapitalized, lat, lon, radius.toDouble()) }
            Logger.info("environment_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envNameCapitalized, "id" to id)
                else mapOf("id" to id),
                correlationId = corrId)
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, cold start cobre).
            MainActivity.notifyDataChanged()
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
                conversationState.armEnvConfirm(title, envName, content)
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
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, cold start cobre).
            MainActivity.notifyDataChanged()
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

    // ── Etapa 2: lembrete por tempo + atualizações (escrita nativa direta) ────

    // Insere um lembrete em scheduled_reminders. Retorna o id (para o chamador
    // agendar o alarme) ou null em falha. scheduled_at/created_at em SEGUNDOS
    // (convenção Drift, lida pelo ReminderReceiver). content sempre '' (paridade Home).
    private fun writeReminderToDb(title: String, scheduledAtMillis: Long, repeatRule: String,
                                  repeatDays: String, alertMode: String): String? {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "write_reminder"),
                correlationId = corrId)
            return null
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "write_reminder"), correlationId = corrId)
            return null
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            val id = UUID.randomUUID().toString()
            val nowSec = System.currentTimeMillis() / 1000L
            val schedSec = scheduledAtMillis / 1000L
            // Capitaliza só a 1a letra (mesma regra do CreateReminderSkill Dart).
            val capTitle = if (title.isEmpty()) title
                else title.substring(0, 1).uppercase(java.util.Locale("pt", "BR")) + title.substring(1)
            db.execSQL(
                "INSERT INTO scheduled_reminders (id, title, content, scheduled_at, repeat_rule, " +
                "repeat_days_of_week, is_active, alert_mode, created_at) VALUES (?, ?, '', ?, ?, ?, 1, ?, ?)",
                arrayOf<Any>(id, capTitle, schedSec, repeatRule, repeatDays, alertMode, nowSec)
            )
            Logger.info("reminder_created", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("title" to capTitle, "id" to id) else mapOf("id" to id),
                correlationId = corrId)
            getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis()).apply()
            MainActivity.notifyDataChanged()
            id
        } catch (e: Exception) {
            Logger.error("sqlite_write_reminder_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start, exception = e, correlationId = corrId)
            logException("command_dispatch", e)
            null
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Atualiza o raio de um ambiente (por nome, case-insensitive) e re-registra o
    // geofence com o novo raio. radius null = mantém o atual (só re-registra).
    // Retorna false se não encontrar (o loop do plano fala o resumo agregado).
    private fun updateEnvironmentInDb(name: String, radius: Int?): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "update_env"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "update_env"), correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            var envId: String? = null
            var lat = 0.0; var lon = 0.0; var envName = name; var curRadius = 100.0
            db.rawQuery(
                "SELECT id, latitude, longitude, name, radius_meters FROM environments " +
                "WHERE LOWER(name) = LOWER(?) LIMIT 1", arrayOf(name)
            ).use { c ->
                if (c.moveToFirst()) {
                    envId = c.getString(0); lat = c.getDouble(1); lon = c.getDouble(2)
                    envName = c.getString(3) ?: name; curRadius = c.getDouble(4)
                }
            }
            val id = envId ?: return false
            val newRadius = radius?.toDouble() ?: curRadius
            db.execSQL("UPDATE environments SET radius_meters = ? WHERE id = ?",
                arrayOf<Any>(newRadius, id))
            mainHandler.post { registerGeofence(id, envName, lat, lon, newRadius) }
            Logger.info("environment_updated", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envName, "radius" to newRadius.toString())
                else mapOf("id" to id), correlationId = corrId)
            getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis()).apply()
            MainActivity.notifyDataChanged()
            true
        } catch (e: Exception) {
            Logger.error("sqlite_update_environment_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start, exception = e, correlationId = corrId)
            logException("command_dispatch", e)
            false
        } finally {
            try { db?.close() } catch (e: Exception) {
                Logger.warn("sqlite_close_failed", feature = "floating_voice", exception = e)
            }
        }
    }

    // Atualiza título e/ou conteúdo de um lembrete existente (match parcial de
    // título no ambiente). Campos ausentes preservam o valor atual (semântica do
    // UpdateTriggerSkill Dart). Retorna false se não encontrar (o loop fala o resumo).
    private fun updateTriggerInDb(envName: String, title: String,
                                  newTitle: String?, content: String?): Boolean {
        val corrId = CorrelationManager.correlationIdFor("voice")
        val dbPath = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString("flutter.sopro_db_path", null) ?: run {
            Logger.error("sqlite_db_path_missing", feature = "floating_voice", action = "db_write",
                payload = mapOf("reason" to "db_path_not_in_prefs", "op" to "update_trigger"),
                correlationId = corrId)
            return false
        }
        val dbFile = File(dbPath)
        if (!dbFile.exists()) {
            Logger.error("sqlite_db_file_not_found", feature = "floating_voice", action = "db_write",
                payload = mapOf("path" to dbPath, "op" to "update_trigger"), correlationId = corrId)
            return false
        }
        var db: SQLiteDatabase? = null
        val start = System.currentTimeMillis()
        return try {
            db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
            var trigId: String? = null; var oldTitle = ""; var oldContent = ""
            db.rawQuery(
                "SELECT t.id, t.title, t.content FROM triggers t " +
                "JOIN environments e ON t.environment_id = e.id " +
                "WHERE LOWER(e.name) = LOWER(?) AND LOWER(t.title) LIKE LOWER(?) LIMIT 1",
                arrayOf(envName, "%$title%")
            ).use { c ->
                if (c.moveToFirst()) {
                    trigId = c.getString(0); oldTitle = c.getString(1) ?: ""; oldContent = c.getString(2) ?: ""
                }
            }
            val id = trigId ?: return false
            val finalTitle = newTitle ?: oldTitle
            val finalContent = content ?: oldContent
            db.execSQL("UPDATE triggers SET title = ?, content = ? WHERE id = ?",
                arrayOf(finalTitle, finalContent, id))
            Logger.info("trigger_updated", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start,
                payload = if (LoggerConfiguration.debugLogging)
                    mapOf("environment_name" to envName, "title" to finalTitle) else null,
                correlationId = corrId)
            getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE).edit()
                .putBoolean("flutter.needs_refresh", true)
                .putLong("flutter.needs_refresh_at", System.currentTimeMillis()).apply()
            MainActivity.notifyDataChanged()
            true
        } catch (e: Exception) {
            Logger.error("sqlite_update_trigger_failed", feature = "floating_voice", action = "db_write",
                durationMs = System.currentTimeMillis() - start, exception = e, correlationId = corrId)
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
                mainHandler.post { speak(OverlayPersona.environmentNotFoundVerify(envNameCapitalized)) }
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
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, needs_refresh cobre).
            MainActivity.notifyDataChanged()
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
                    mainHandler.post { speak(OverlayPersona.reminderNotFoundIn(envNameCapitalized)) }
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
            // Push: se o app estiver vivo, atualiza a UI na hora (senão, cold start cobre).
            MainActivity.notifyDataChanged()
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
        // TEMP: remover após calibração da resolução de localização
        Logger.info("geofence_registration_request", feature = "floating_voice", action = "geofence",
            payload = mapOf("environment" to name, "lat" to lat.toString(),
                "lng" to lon.toString(), "radius" to radius.toString()))
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
                    // TEMP: remover após calibração da resolução de localização
                    Logger.info("geofence_registration_success", feature = "floating_voice", action = "geofence",
                        payload = mapOf("environment" to name, "lat" to lat.toString(),
                            "lng" to lon.toString()))
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
                // HOTFIX 2 — charset explícito evita mojibake nos acentos (UTF-8 lido como Latin-1)
                setRequestProperty("Content-Type",  "application/json; charset=utf-8")
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
        // Grava timestamp SEMPRE (dedup do Home), qualquer que seja o motor usado.
        getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_FLOATING_SPOKE, System.currentTimeMillis()).apply()

        // Voz Piper faber-medium (idêntica ao Home) via OverlayTts. Se a carga ou
        // a geração falhar, cai no TTS nativo do sistema — overlay nunca fica mudo.
        // O TextToSpeech nativo não é thread-safe fora da main thread, então o
        // fallback é postado no mainHandler.
        OverlayTts.speak(applicationContext, text) { ok ->
            if (!ok) {
                mainHandler.post {
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "sopro_utt")
                }
            }
        }
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
