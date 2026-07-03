package com.sopro.sopro

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.MediaRecorder
import android.os.*
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

// FloatingVoiceService — botão circular flutuante de voz sobre todos os apps.
//
// Diferente da versão anterior (que abria o app), este serviço grava o áudio
// diretamente, envia ao Gemini via HTTP e escreve o trigger no banco SQLite —
// tudo sem abrir o app ou mudar o foco do usuário.
//
// Fluxo de uso:
//   1. Toque simples → alterna gravação on/off (mesmo gesto do WhatsApp)
//   2. Arraste → reposiciona o botão na tela (posição salva em SharedPreferences)
//   3. Após soltar: áudio → Gemini → JSON → trigger criado → Toast de confirmação
//
// Visibilidade:
//   - Botão OCULTO quando qualquer Activity do Sopro está em foreground
//     (ActivityLifecycleCallbacks — não precisa de Application personalizada)
//   - Botão VISÍVEL quando o Sopro está em background ou fechado
//
// Ciclo de vida:
//   - Iniciado via MethodChannel "com.sopro.sopro/overlay"
//   - Parado via MethodChannel ou toggle nas Configurações
//   - Reiniciado no próximo startup pelo AppInitializer se floating_voice_enabled=true
class FloatingVoiceService : Service() {

    companion object {
        private const val TAG       = "FloatingVoiceService"
        const val EXTRA_OPEN_VOICE  = "OPEN_VOICE"  // mantido para compatibilidade de intent

        private const val NOTIF_ID   = 9001
        private const val CHANNEL_ID = "sopro_background"

        // SharedPreferences do Flutter (prefixo "flutter.") — onde lemos a API key do Gemini
        private const val FLUTTER_PREFS     = "FlutterSharedPreferences"
        // Chave onde o AppInitializer salva a Gemini API key para uso nativo
        private const val KEY_GEMINI_API    = "flutter.gemini_api_key"
        // Posição salva do botão
        private const val PREF_FILE         = "sopro_float_pos"
        private const val KEY_BTN_X         = "btn_x"
        private const val KEY_BTN_Y         = "btn_y"

        // Endpoint Gemini — mesmo modelo usado pelo Dart
        private const val GEMINI_ENDPOINT =
            "https://generativelanguage.googleapis.com/v1beta/models/" +
            "gemini-2.5-flash-preview-05-20:generateContent"
    }

    // ── Views e WindowManager ─────────────────────────────────────────────────
    private var windowManager: WindowManager? = null
    private var containerView: FrameLayout?   = null
    private var waveView:      View?          = null
    private var btnView:       ImageView?     = null
    private var layoutParams:  WindowManager.LayoutParams? = null

    // ── Estado de arraste / toque ─────────────────────────────────────────────
    private var dragStartX  = 0f
    private var dragStartY  = 0f
    private var initParamX  = 0
    private var initParamY  = 0
    private var isDragging  = false

    // Instante em que o dedo toca a tela — para distinguir toque curto de hold
    private var pressStartTime: Long = 0L
    // Runnable que inicia a gravação após 300 ms de hold (cancelado se arrastar)
    private var recordingStartRunnable: Runnable? = null

    // ── Gravação ──────────────────────────────────────────────────────────────
    private var mediaRecorder: MediaRecorder? = null
    private var audioFile:     File?          = null
    private var isRecording                   = false

    // ── Handlers ──────────────────────────────────────────────────────────────
    private val mainHandler = Handler(Looper.getMainLooper())
    private val waveHandler = Handler(Looper.getMainLooper())

    // ── Animação de onda ──────────────────────────────────────────────────────
    private var waveScale   = 1.0f
    private var waveGrowing = true

    // ── ActivityLifecycleCallbacks — esconde botão quando Sopro está em foco ──
    private var soperoActivitiesVisible = 0
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) {
            soperoActivitiesVisible++
            mainHandler.post { containerView?.visibility = View.GONE }
        }
        override fun onActivityStopped(activity: Activity) {
            soperoActivitiesVisible--
            if (soperoActivitiesVisible <= 0) {
                // Aguarda 200 ms para evitar flicker durante navegação entre telas
                mainHandler.postDelayed({
                    containerView?.visibility = View.VISIBLE
                }, 200)
            }
        }
        // Callbacks obrigatórios sem uso
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
            stopSelf()
            return
        }

        // Foreground obrigatório no Android 8+ para sobreviver em background
        startForeground(NOTIF_ID, buildSilentNotification())
        createOverlayButton()

        // Registra no contexto da Application para receber eventos de Activity
        (applicationContext as Application).registerActivityLifecycleCallbacks(lifecycleCallbacks)

        Log.d(TAG, "FloatingVoiceService iniciado — botão circular criado")
    }

    override fun onDestroy() {
        (applicationContext as Application).unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        stopRecordingIfActive()
        waveHandler.removeCallbacksAndMessages(null)
        mainHandler.removeCallbacksAndMessages(null)
        removeOverlayButton()
        Log.d(TAG, "FloatingVoiceService encerrado")
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Notificação foreground mínima
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

        val btnPx  = dpToPx(56) // botão principal 56 dp
        val wavePx = dpToPx(80) // anel de onda um pouco maior

        // Anel de onda atrás do botão — aparece e pulsa durante a gravação
        val wave = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x40E8445A.toInt()) // accent 25% de opacidade
            }
            alpha = 0f // oculto inicialmente
        }
        waveView = wave

        // Botão circular com ícone do app
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

        // Container FrameLayout — wavePx × wavePx (centraliza onda e botão)
        val container = FrameLayout(this)
        containerView = container

        container.addView(wave, FrameLayout.LayoutParams(wavePx, wavePx).apply {
            gravity = Gravity.CENTER
        })
        container.addView(btn, FrameLayout.LayoutParams(btnPx, btnPx).apply {
            gravity = Gravity.CENTER
        })

        // Restaura posição salva ou calcula posição padrão (canto inferior direito)
        // Com gravity TOP|START, x e y são offsets do canto superior esquerdo
        val (defX, defY) = defaultButtonPosition(wavePx)
        val pos    = getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val savedX = pos.getInt(KEY_BTN_X, defX)
        val savedY = pos.getInt(KEY_BTN_Y, defY)

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            wavePx, wavePx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            // TOP|START: x e y são offsets absolutos do canto superior esquerdo.
            // Permite movimento livre horizontal E vertical sem inversão de eixo.
            gravity = Gravity.TOP or Gravity.START
            x = savedX
            y = savedY
        }
        layoutParams = params

        // Touch listener: arraste = reposicionar; toque = gravar/parar
        container.setOnTouchListener { _, event -> handleTouch(event); true }

        windowManager?.addView(container, params)
    }

    // Cria um GradientDrawable oval (círculo) com a cor especificada
    private fun circleDrawable(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    private fun removeOverlayButton() {
        containerView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        containerView = null
        windowManager = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tratamento de toque — arraste vs. gravação
    // ─────────────────────────────────────────────────────────────────────────

    // Toque: SEGURAR para gravar, SOLTAR para processar (estilo WhatsApp).
    //
    // Fluxo:
    //   ACTION_DOWN → salva coordenadas + agenda startRecording() após 300 ms
    //   ACTION_MOVE > 8dp → isDragging=true, cancela gravação agendada, reposiciona
    //   ACTION_UP   → se !dragging e gravando → processa; se curto → Toast
    //   ACTION_CANCEL → cancela tudo
    private fun handleTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                // Salva posição inicial do dedo e do botão
                dragStartX  = event.rawX
                dragStartY  = event.rawY
                initParamX  = layoutParams?.x ?: 0
                initParamY  = layoutParams?.y ?: 0
                isDragging  = false
                pressStartTime = System.currentTimeMillis()

                // Agenda início de gravação após 300 ms; cancela se arrastar antes
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                val run = Runnable { if (!isDragging) startRecording() }
                recordingStartRunnable = run
                mainHandler.postDelayed(run, 300L)
            }

            MotionEvent.ACTION_MOVE -> {
                // FIX 1: com gravity TOP|START, dy positivo = move para baixo
                val dx = (event.rawX - dragStartX).toInt()
                val dy = (event.rawY - dragStartY).toInt()

                if (!isDragging && (Math.abs(dx) > dpToPx(8) || Math.abs(dy) > dpToPx(8))) {
                    isDragging = true
                    // Cancela gravação agendada (usuário está arrastando, não gravando)
                    recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                    recordingStartRunnable = null
                    // Se gravação já começou (raro): cancela
                    if (isRecording) { stopRecordingIfActive(); onRecordingCancelled() }
                }

                if (isDragging) {
                    // FIX 1: atualiza AMBOS os eixos com offset absoluto
                    layoutParams?.let { p ->
                        p.x = initParamX + dx
                        p.y = initParamY + dy
                        try { windowManager?.updateViewLayout(containerView, p) }
                        catch (_: Exception) {}
                    }
                }
            }

            MotionEvent.ACTION_UP -> {
                // Cancela Runnable pendente (pode ainda não ter disparado)
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null

                if (isDragging) {
                    // Salva nova posição persistida
                    layoutParams?.let { p ->
                        getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                            .edit().putInt(KEY_BTN_X, p.x).putInt(KEY_BTN_Y, p.y).apply()
                    }
                    isDragging = false
                } else {
                    val duration = System.currentTimeMillis() - pressStartTime
                    if (isRecording) {
                        // Estava gravando → processa o áudio capturado
                        stopAndProcess()
                    } else if (duration < 300L) {
                        // Toque curto (< 300 ms): gravação não chegou a iniciar
                        showToast("Segure para gravar")
                    }
                    // duration >= 300ms e !isRecording = race condition extremamente rara; ignora
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                recordingStartRunnable?.let { mainHandler.removeCallbacks(it) }
                recordingStartRunnable = null
                if (isRecording) { stopRecordingIfActive(); onRecordingCancelled() }
                isDragging = false
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gravação de áudio (MediaRecorder)
    // ─────────────────────────────────────────────────────────────────────────

    private fun startRecording() {
        if (isRecording) return

        // FIX 2: verifica permissão de microfone antes de qualquer operação
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            showToast("Permissão de microfone necessária")
            Log.w(TAG, "RECORD_AUDIO não concedido — gravação cancelada")
            return
        }

        // FIX 2: filename com timestamp evita corrupção se múltiplas gravações ocorrerem
        audioFile = File(cacheDir, "floating_voice_${System.currentTimeMillis()}.m4a").also {
            if (it.exists()) it.delete()
        }

        try {
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                MediaRecorder(this)
            else @Suppress("DEPRECATION") MediaRecorder()

            mediaRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(8000)   // 8 kHz — qualidade de voz
                setAudioEncodingBitRate(12000) // 12 kbps — arquivo minúsculo (~1 KB/s)
                setOutputFile(audioFile!!.absolutePath)
                prepare()
                start()
            }

            isRecording = true

            // Feedback visual: botão fica vermelho e anel de onda aparece
            btnView?.background = circleDrawable(0xFFE53935.toInt())
            startWaveAnimation()

            // Auto-stop após 10 s (segurança)
            mainHandler.postDelayed({ stopAndProcess() }, 10_000L)

            Log.d(TAG, "Gravação iniciada em ${audioFile!!.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao iniciar MediaRecorder: ${e.message}")
            showToast("Erro ao acessar microfone")
            isRecording = false
        }
    }

    private fun stopAndProcess() {
        if (!isRecording) return
        mainHandler.removeCallbacksAndMessages(null)
        stopRecordingIfActive()

        // Restaura aparência do botão (accent color)
        btnView?.background = circleDrawable(0xFFE8445A.toInt())
        stopWaveAnimation()

        val file = audioFile
        if (file == null || !file.exists() || file.length() == 0L) {
            showToast("Áudio vazio — tente novamente")
            return
        }

        Log.d(TAG, "Áudio capturado: ${file.length()} bytes — enviando ao Gemini")
        Thread { processAudio(file) }.start()
    }

    private fun stopRecordingIfActive() {
        if (!isRecording) return
        isRecording = false
        try {
            mediaRecorder?.apply { stop(); release() }
        } catch (e: Exception) {
            Log.e(TAG, "MediaRecorder stop error: ${e.message}")
        }
        mediaRecorder = null
    }

    private fun onRecordingCancelled() {
        btnView?.background = circleDrawable(0xFFE8445A.toInt())
        stopWaveAnimation()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gemini Audio API
    // ─────────────────────────────────────────────────────────────────────────

    private fun processAudio(file: File) {
        val apiKey = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_GEMINI_API, "") ?: ""

        if (apiKey.isEmpty()) {
            Log.w(TAG, "Gemini API key ausente — abra o app Sopro primeiro")
            showToast("Abra o Sopro pelo menos uma vez para configurar")
            return
        }

        val audioBase64 = Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)
        val systemPrompt = buildSystemPrompt()

        val body = JSONObject().apply {
            put("contents", JSONArray().apply {
                put(JSONObject().apply {
                    put("parts", JSONArray().apply {
                        put(JSONObject().put("text", systemPrompt))
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
                put("temperature", 0)
                put("maxOutputTokens", 256)
            })
        }.toString()

        try {
            val url  = URL("$GEMINI_ENDPOINT?key=$apiKey")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 30_000
                readTimeout    = 30_000
                doOutput       = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(body.toByteArray()) }

            val code = conn.responseCode
            if (code == 200) {
                val raw = conn.inputStream.bufferedReader().readText()
                parseAndExecute(raw)
            } else {
                val err = conn.errorStream?.bufferedReader()?.readText() ?: ""
                Log.e(TAG, "Gemini HTTP $code: $err")
                showToast("Erro ao processar (HTTP $code)")
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Gemini request error: $e")
            showToast("Sem conexão com a internet")
        }
    }

    // Prompt simplificado — o serviço nativo só suporta create_trigger
    private fun buildSystemPrompt(): String {
        // Reutiliza os nomes de ambiente salvos pelo GeofenceReceiver nas SharedPreferences
        val envNames = getSharedPreferences(GeofenceReceiver.PREFS_NAME, Context.MODE_PRIVATE)
            .all.values.filterIsInstance<String>()
        val envCtx = if (envNames.isNotEmpty())
            "\nAmbientes cadastrados: ${envNames.joinToString(", ")}." else ""

        return """
Extraia a intenção do áudio em JSON. Responda APENAS com JSON, sem markdown.
Schemas:
  create_trigger: {"intent":"create_trigger","environment":"nome_exato","trigger":{"title":"acao_infinitivo","content":""}}
  unknown: {"intent":"unknown","transcricao":"texto"}

Regra de título: SOMENTE a ação (max 50 chars, infinitivo, sem pronomes).
Exemplo: "lembra de comprar leite quando eu chegar em casa" → title="comprar leite"$envCtx
""".trimIndent()
    }

    private fun parseAndExecute(raw: String) {
        try {
            val text = JSONObject(raw)
                .getJSONArray("candidates")
                .getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .getString("text")
                .replace(Regex("```[a-zA-Z]*\\n?"), "")
                .replace("```", "")
                .trim()

            val parsed = JSONObject(text)
            when (parsed.optString("intent")) {
                "create_trigger" -> {
                    val envName = parsed.optString("environment", "")
                    val trigger = parsed.optJSONObject("trigger")
                    val title   = trigger?.optString("title", "") ?: ""
                    val content = trigger?.optString("content", "") ?: ""

                    if (envName.isNotEmpty() && title.isNotEmpty()) {
                        createTriggerInDb(envName, title, content)
                    } else {
                        showToast("Não entendi o comando de voz")
                    }
                }
                else -> showToast("Não entendi. Abra o Sopro para comandos avançados.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao parsear resposta Gemini: $e")
            showToast("Erro ao interpretar resposta")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Escrita direta no banco SQLite (sem Flutter Engine)
    // ─────────────────────────────────────────────────────────────────────────

    // Mesmo padrão de caminhos do BootReceiver — Drift armazena o banco em
    // getApplicationDocumentsDirectory() que no Android é filesDir.parent/app_flutter/
    private fun createTriggerInDb(envName: String, title: String, content: String) {
        val candidates = listOf(
            File(filesDir.parentFile, "app_flutter/sopro.db"),
            File(filesDir, "sopro.db"),
            getDatabasePath("sopro.db"),
        )
        val dbFile = candidates.firstOrNull { it.exists() } ?: run {
            Log.w(TAG, "sopro.db não encontrado para criar trigger")
            showToast("Abra o Sopro pelo menos uma vez")
            return
        }

        try {
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE
            ).use { db ->
                // Busca o ID do ambiente por nome (case-insensitive)
                val envId = db.rawQuery(
                    "SELECT id FROM environments WHERE LOWER(name) = LOWER(?)",
                    arrayOf(envName)
                ).use { c -> if (c.moveToFirst()) c.getString(0) else null }

                if (envId == null) {
                    Log.w(TAG, "Ambiente '$envName' não encontrado")
                    showToast("Local '$envName' não encontrado no Sopro")
                    return
                }

                val triggerId = UUID.randomUUID().toString()
                db.execSQL(
                    "INSERT INTO triggers (id, environment_id, title, content, is_active, created_at)" +
                    " VALUES (?, ?, ?, ?, 1, ?)",
                    arrayOf(triggerId, envId, title, content, System.currentTimeMillis())
                )
                Log.d(TAG, "Trigger '$title' criado em '$envName' (db direto)")
                showToast("Anotado! Vou te lembrar de $title em $envName ✓")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao criar trigger no banco: $e")
            showToast("Erro ao salvar lembrete")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Animação do anel de onda durante gravação
    // ─────────────────────────────────────────────────────────────────────────

    private fun startWaveAnimation() {
        waveScale   = 1.0f
        waveGrowing = true
        waveView?.alpha = 0.6f
        animateWave()
    }

    private fun animateWave() {
        if (!isRecording) return
        val step = 0.04f
        if (waveGrowing) {
            waveScale += step
            if (waveScale >= 1.4f) { waveScale = 1.4f; waveGrowing = false }
        } else {
            waveScale -= step
            if (waveScale <= 1.0f) { waveScale = 1.0f; waveGrowing = true }
        }
        // Alpha diminui conforme a onda expande (1.4→0.0, 1.0→0.6)
        val alpha = (1.4f - waveScale) / 0.4f * 0.6f
        waveView?.let { v -> v.scaleX = waveScale; v.scaleY = waveScale; v.alpha = alpha }
        waveHandler.postDelayed({ animateWave() }, 32L) // ~30 fps
    }

    private fun stopWaveAnimation() {
        waveHandler.removeCallbacksAndMessages(null)
        waveView?.apply { scaleX = 1f; scaleY = 1f; alpha = 0f }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utilitários
    // ─────────────────────────────────────────────────────────────────────────

    private fun showToast(msg: String) {
        mainHandler.post { Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show() }
    }

    // Calcula posição padrão no canto inferior direito com gravity TOP|START.
    // wavePx = tamanho do container, margens de 24dp (direita) e 96dp (baixo).
    private fun defaultButtonPosition(wavePx: Int): Pair<Int, Int> {
        val dm = resources.displayMetrics
        val x  = (dm.widthPixels  - wavePx - dpToPx(24)).coerceAtLeast(0)
        val y  = (dm.heightPixels - wavePx - dpToPx(96)).coerceAtLeast(0)
        return Pair(x, y)
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density + 0.5f).toInt()
}
