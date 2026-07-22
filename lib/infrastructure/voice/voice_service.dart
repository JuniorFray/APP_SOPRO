import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sopro/core/constants/app_constants.dart';
import 'package:sopro/infrastructure/logging/core/correlation_manager.dart';
import 'package:sopro/infrastructure/logging/core/logger.dart';
import 'package:sopro/infrastructure/voice/execution_plan.dart';

// Intenções de voz que o app sabe executar.
// Schemas Gemini correspondentes: ver AppConstants.geminiSystemPrompt.
enum VoiceIntent {
  // "lembra de X quando eu chegar em Y"
  createTrigger,
  // "salva esse lugar como X" / "cria um ambiente chamado X"
  createEnvironment,
  // "quando eu chegar em X lembra de Y e também Z" — cria ambiente + gatilhos juntos
  createEnvironmentWithTrigger,
  // "muda o raio de X para 200" / "atualiza o ambiente X"
  updateEnvironment,
  // "quais são meus locais"
  listEnvironments,
  // "resolvi X" / "pode apagar X"
  resolveTrigger,
  // "o que tenho pendente em X?"
  listTriggers,
  // "exclui o ambiente X" — requer confirmação (ação irreversível)
  deleteEnvironment,
  // "remove o lembrete de Y" — exclui trigger por título
  deleteTrigger,
  // "apaga todos os gatilhos de X" — requer confirmação
  deleteAllTriggers,
  // "apaga todos os ambientes" / "limpar ambientes" — operação global, requer confirmação
  // (Fase 1 — assistente inteligente). Não tem environment associado: atinge tudo.
  deleteAllEnvironments,
  // comando não classificado — fallback para texto livre
  fallback,
}

// Resultado do processamento de intenção de voz.
class VoiceResult {
  // Intenção detectada (enum)
  final VoiceIntent intent;
  // Transcrição do áudio retornada pelo Gemini (ou texto editado manualmente)
  final String transcript;
  // Título/ação do lembrete (createTrigger, resolveTrigger)
  final String? triggerAction;
  // Conteúdo detalhado do gatilho (createTrigger) — opcional
  final String? triggerContent;
  // Nome do ambiente extraído do comando
  final String? environmentName;
  // Raio em metros para criar/atualizar ambiente (createEnvironment, updateEnvironment)
  final int? environmentRadius;
  // Lista de títulos de gatilhos para criar junto com o ambiente
  final List<String> triggerTitles;

  const VoiceResult({
    required this.intent,
    required this.transcript,
    this.triggerAction,
    this.triggerContent,
    this.environmentName,
    this.environmentRadius,
    this.triggerTitles = const [],
  });
}

// Fase 2 — resultado estruturado do assistente: resposta natural + plano de ações.
// Substitui a lógica "1 fala = 1 intent" pelo modelo "1 fala = N ações + fala".
// [legacyResult] só é preenchido quando o Gemini devolve o schema antigo (intent),
// garantindo retrocompatibilidade total com a Fase 1.
class VoicePlanResult {
  final String transcript;               // texto falado (STT)
  final String reply;                    // resposta natural para TTS
  final ExecutionPlan plan;              // ações a executar em sequência
  final String? followUp;                // pergunta final opcional
  final Map<String, dynamic> contextUpdates; // atualizações de contexto sugeridas
  final VoiceResult? legacyResult;       // != null se veio no schema antigo (intent)

  const VoicePlanResult({
    required this.transcript,
    required this.reply,
    required this.plan,
    this.followUp,
    this.contextUpdates = const {},
    this.legacyResult,
  });

  // Resultado neutro (erro/rede/arquivo vazio) — o caller trata como "nada a fazer".
  factory VoicePlanResult.empty() =>
      const VoicePlanResult(transcript: '', reply: '', plan: ExecutionPlan([]));

  // True quando não há ação, nem resposta, nem intent legado — nada para responder.
  bool get hasNothing =>
      plan.isEmpty && reply.trim().isEmpty && legacyResult == null;
}

// Gerencia gravação de áudio e síntese de voz (TTS) on-device.
// Processamento de intenção via Gemini Audio API (STT + NLU em uma chamada).
// Fallback para regex local quando Gemini não está disponível.
class VoiceService {
  // Engine de gravação de áudio (pacote record ^5.x)
  final _recorder = AudioRecorder();
  // Engine de síntese de voz on-device (flutter_tts)
  final _tts = FlutterTts();
  // Flag para evitar múltiplas inicializações do TTS
  bool _ttsReady = false;

  // ── Auto-stop (silêncio + duração máxima) ────────────────────────────────
  // StreamController notifica o FAB quando o serviço encerra a gravação automaticamente.
  final _autoStopController = StreamController<void>.broadcast();
  // Timer de duração máxima (10 s)
  Timer? _maxDurationTimer;
  // Timer de silêncio — dispara após 1500 ms consecutivos abaixo do limiar
  Timer? _silenceTimer;
  // Subscription da stream de amplitude para detecção de silêncio
  StreamSubscription<Amplitude>? _amplitudeSub;
  // Evita disparar auto-stop múltiplas vezes se timers se sobrepuserem
  bool _autoStopFired = false;

  // HOTFIX 1 (Fase 2) — true se alguma amplitude cruzou o limiar de fala durante
  // a gravação atual. Objetivo: NUNCA enviar áudio sem fala ao Gemini. In-app não
  // tem STT antes do Gemini (pipeline é áudio→Gemini), então usamos a amplitude já
  // monitorada para detecção de silêncio como gate. Resetado a cada startRecording.
  bool _speechDetected = false;

  // Exposto para os callers gate-arem o processamento (processAudio/transcribeAudio)
  // ANTES de qualquer chamada Gemini quando não houve fala real.
  bool get speechDetected => _speechDetected;

  // GATE DE ENVIO — leitura do estado do gate adaptativo para a DECISÃO ÚNICA de
  // enviar (ou não) ao Gemini (home_gate_decision). Apenas getters: NÃO alteram
  // a calibração, os limiares nem a sensibilidade.
  int get speechFrames => _speechFrames;
  double? get noiseFloorDb => _noiseFloorDb;
  double? get gateThresholdDb =>
      _noiseFloorDb == null ? null : _noiseFloorDb! + _speechMarginDb;
  bool get noiseCalibrated => _noiseFloorDb != null;
  // Mínimo de frames sustentados exigido — exposto para o gate de decisão.
  static const int minSpeechFramesRequired = _minSpeechFrames;

  // GATE ADAPTATIVO (noise floor) — substitui os limiares FIXOS. Motivo: cada
  // microfone tem sensibilidade diferente, então -30/-24 dBFS fixos bloqueavam
  // fala baixa/sussurro em uns aparelhos e vazavam ruído em outros. Agora medimos
  // o RUÍDO AMBIENTE nos primeiros ~500 ms e detectamos fala só quando a energia
  // supera noiseFloor + margem (estilo Alexa/Google). Fala continua exigindo
  // SUSTENTAÇÃO (nº de frames) + um PICO — mas RELATIVOS ao ruído medido.
  int _speechFrames = 0;         // frames acima do limiar adaptativo
  double _maxAmplitude = -160.0; // pico de amplitude da sessão (dBFS)
  int _warmupFrames = 0;         // frames iniciais ignorados (transiente do mic)
  int _calibFrames = 0;          // frames já usados p/ medir o ruído ambiente
  double _noiseAccumDb = 0.0;    // soma das energias na janela de calibração
  double? _noiseFloorDb;         // média do ruído ambiente (null até calibrar)
  static const int    _warmupFrameCount = 2;   // ~200 ms — paridade c/ delay do Overlay
  static const int    _calibFrameCount = 5;    // ~500 ms (frames de 100 ms)
  static const double _speechMarginDb  = 6.8;  // fala = ruído + 6.8 dB (BUG 3: -15% p/ aceitar fala baixa/sussurro)
  static const double _peakMarginDb    = 10.2; // pico exigido = ruído + 10.2 dB (BUG 3: -15%)
  static const int    _minSpeechFrames = 3;    // ≈ 300 ms de fala sustentada
  // Piso do noiseFloor (paridade c/ MIN_NOISE_FLOOR do Overlay). Impede que um
  // vale de silêncio degenere o threshold. Equivale a ~-41 dBFS do Overlay; -45
  // é um pouco mais permissivo p/ não bloquear sussurro em sala silenciosa.
  static const double _minNoiseFloorDb = -45.0;

  // O FAB escuta este stream e chama _stopAndProcess() ao receber o evento.
  Stream<void> get onAutoStop => _autoStopController.stream;

  // ── Padrões regex para português brasileiro ────────────────────────────────
  // Usados como fallback quando Gemini não está disponível (sem chave/internet).

  // "lembra de [ação] quando eu chegar em [ambiente]"
  static final _regexCreate = RegExp(
    r'lembr[ae](?:[-\s]me)?(?:\s+de)?\s+(.+?)\s+quando\s+(?:eu\s+)?chegar?\s+(?:em|no|na|ao|à|nos|nas)\s+(.+)',
  );

  // "salva esse lugar como [nome]" / "cria um ambiente chamado [nome]"
  static final _regexOpenEnv = RegExp(
    r'(?:salv[ae]\s+(?:esse|este)\s+lugar|cri[ae]\s+(?:um\s+)?(?:ambiente|lugar)(?:\s+aqui)?)\s+(?:como|chamado)\s+(.+)',
  );

  // "resolvi [título]" / "pode apagar [título]"
  static final _regexResolve = RegExp(
    r'(?:resolvi|pode\s+apagar|remov[ae]|delet[ae]|apag[au])\s+(.+)',
  );

  // "o que tenho pendente em [ambiente]?"
  static final _regexList = RegExp(
    r'(?:o\s+que\s+(?:tenho|tem)\s+(?:pendente|para\s+fazer)|quais\s+(?:são\s+)?(?:os\s+)?(?:gatilhos|lembretes))\s+(?:em|no|na|do|da|nos|nas)\s+(.+)',
  );

  // ── Gravação ──────────────────────────────────────────────────────────────

  // Verifica se a permissão de microfone foi concedida.
  Future<bool> hasPermission() async => _recorder.hasPermission();

  // Inicia gravação em arquivo temporário (AAC/M4A, 8 kHz, 12 kbps).
  // Qualidade de voz é suficiente para STT; tamanho resultante ~1 KB/s
  // (alvo: <15 KB para comando de 10 s, vs 244 KB anteriores a 64 kbps).
  //
  // Sprint Unificação da Captura: [holdToTalk] = true faz o DEDO ser o único fim
  // de gravação — desliga o VAD (timer de silêncio) e o teto de duração automático.
  // Enquanto o botão estiver pressionado o áudio continua sendo gravado, mesmo com
  // silêncio ou pausas (Regras 1-4). O modo padrão (false) mantém o auto-stop por
  // silêncio/tempo usado pelos campos de formulário que transcrevem trechos curtos.
  // Retorna true se a gravação iniciou com sucesso.
  Future<bool> startRecording({bool holdToTalk = false}) async {
    try {
      // Verifica permissão antes de iniciar
      if (!await _recorder.hasPermission()) {
        debugPrint('[VoiceService] Permissão de microfone negada');
        return false;
      }
      // Usa diretório temporário do app — não requer permissão de storage
      final dir   = await getTemporaryDirectory();
      final path  = '${dir.path}/sopro_voice.m4a';
      // Remove gravação anterior se existir (evita acúmulo de arquivos temp)
      final prev = File(path);
      if (await prev.exists()) await prev.delete();

      _autoStopFired = false;
      _speechDetected = false; // HOTFIX 1 — zera detecção de fala da sessão anterior
      _speechFrames = 0;       // zera contagem/pico da sessão
      _maxAmplitude = -160.0;
      _warmupFrames = 0;       // GATE ADAPTATIVO — reinicia warmup/calibração
      _calibFrames = 0;
      _noiseAccumDb = 0.0;
      _noiseFloorDb = null;

      await _recorder.start(
        const RecordConfig(
          encoder:    AudioEncoder.aacLc, // M4A/AAC compatível com Gemini
          bitRate:    12000,              // 12 kbps — voz inteligível, arquivo minúsculo
          sampleRate: 8000,              // 8 kHz = qualidade telefônica, ok para STT
        ),
        path: path,
      );

      // Teto de duração automático: SOMENTE fora do modo hold-to-talk. No assistente
      // (holdToTalk) o dedo controla o fim — nenhum timer interrompe a gravação.
      _maxDurationTimer?.cancel();
      if (!holdToTalk) {
        _maxDurationTimer = Timer(
          const Duration(seconds: 10),
          () => _fireAutoStop('max_duration'),
        );
      }

      // Monitora amplitude sempre (marca _speechDetected para o gate da Regra 9),
      // mas só ARMA o timer de silêncio (VAD) fora do modo hold-to-talk. Em
      // hold-to-talk, silêncio/pausas NUNCA encerram a gravação.
      _silenceTimer?.cancel();
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        final cur = amp.current;
        if (cur > _maxAmplitude) _maxAmplitude = cur;

        // VAD de silêncio (só campos de formulário, !holdToTalk) — limiar -35 dBFS
        // MANTIDO para não regredir a auto-parada por silêncio dos trechos curtos.
        if (cur < -35.0) {
          if (!holdToTalk) {
            _silenceTimer ??= Timer(
              const Duration(milliseconds: 1500),
              () => _fireAutoStop('silence'),
            );
          }
        } else {
          _silenceTimer?.cancel();
          _silenceTimer = null;
        }

        // GATE ADAPTATIVO — ignora os primeiros frames (transiente de ativação do
        // mic). Paridade com o atraso de 250 ms do Overlay: sem isto, o vale inicial
        // puxa o noiseFloor para baixo e degenera o threshold (causa do falso positivo).
        if (_warmupFrames < _warmupFrameCount) {
          _warmupFrames++;
          return;
        }

        // Janela de calibração (~500 ms): mede o ruído ambiente e AINDA NÃO detecta fala.
        if (_calibFrames < _calibFrameCount) {
          _calibFrames++;
          _noiseAccumDb += cur;
          if (_calibFrames == _calibFrameCount) {
            var floor = _noiseAccumDb / _calibFrameCount;
            // Piso (paridade Overlay): noiseFloor nunca abaixo de _minNoiseFloorDb,
            // senão o threshold cai sob o ruído do próprio silêncio e tudo passa.
            if (floor < _minNoiseFloorDb) floor = _minNoiseFloorDb;
            _noiseFloorDb = floor;
          }
          return; // durante a calibração não há detecção de fala
        }

        // Pós-calibração: fala quando a energia supera o ruído + margem.
        final floor     = _noiseFloorDb!;
        final threshold = floor + _speechMarginDb;
        if (cur > threshold) _speechFrames++;
        // Exige fala sustentada + um pico RELATIVO ao ruído (não valor fixo).
        if (_speechFrames >= _minSpeechFrames &&
            _maxAmplitude >= floor + _peakMarginDb) {
          _speechDetected = true;
        }
      });

      return true;
    } catch (e, st) {
      Logger.error('voice_record_start_failed',
          exception: e, stackTrace: st, feature: 'voice', action: 'record_start');
      debugPrint('[VoiceService] Erro ao iniciar gravação: $e');
      return false;
    }
  }

  // Dispara o auto-stop exatamente uma vez, cancela todos os timers e notifica o FAB.
  // [reason]: 'max_duration' ou 'silence' (para diagnóstico em log).
  void _fireAutoStop(String reason) {
    if (_autoStopFired) return;
    _autoStopFired = true;
    debugPrint('[VoiceService] Auto-stop disparado: $reason');
    _cancelAutoStopTimers(); // cancela timers antes de emitir
    _autoStopController.add(null); // sinaliza o FAB para parar e processar
  }

  // Cancela timers internos de auto-stop (sem parar o recorder — responsabilidade do FAB).
  void _cancelAutoStopTimers() {
    _maxDurationTimer?.cancel(); _maxDurationTimer = null;
    _silenceTimer?.cancel();     _silenceTimer = null;
    _amplitudeSub?.cancel();     _amplitudeSub = null;
  }

  // Para a gravação e retorna o caminho do arquivo gerado.
  // Cancela timers internos antes de parar para evitar auto-stop duplo.
  // Retorna null se a gravação não estava ativa ou ocorreu erro.
  Future<String?> stopRecording() async {
    _cancelAutoStopTimers(); // cancela antes de parar (evita race condition)
    try {
      return await _recorder.stop();
    } catch (e, st) {
      Logger.warn('voice_record_stop_failed',
          exception: e, stackTrace: st, feature: 'voice', action: 'record_stop');
      debugPrint('[VoiceService] Erro ao parar gravação: $e');
      return null;
    }
  }

  // Cancela a gravação sem processar (usuário descartou ou arrastou para cima).
  Future<void> cancelRecording() async {
    _cancelAutoStopTimers();
    try {
      await _recorder.cancel();
    } catch (e, st) {
      Logger.warn('voice_record_cancel_failed',
          exception: e, stackTrace: st, feature: 'voice', action: 'record_cancel');
      debugPrint('[VoiceService] Erro ao cancelar gravação: $e');
    }
  }

  // true enquanto o engine está gravando ativamente
  Future<bool> get isRecording => _recorder.isRecording();

  // ── Gemini Audio ──────────────────────────────────────────────────────────

  // Lê o arquivo de áudio, envia ao Gemini Audio API e retorna VoiceResult.
  // existingEnvironments: lista de nomes de ambientes já cadastrados, injetada
  // no prompt para que o Gemini retorne o nome EXATO que existe no banco.
  // Loga 'voice_debug' no Supabase com: audio_size_bytes, model_used,
  // gemini_http, gemini_raw (resposta bruta), gemini_error e final_intent.
  Future<VoiceResult> processAudio(
    String filePath, {
    List<String> existingEnvironments = const [],
  }) async {
    final file = File(filePath);
    final correlationId = CorrelationManager.beginOperation('voice');

    // Mapa de diagnóstico logado ao final.
    final debug = <String, dynamic>{
      'audio_size_bytes':   0,
      'model_used':         AppConstants.geminiModel,
      'gemini_http':        null,
      'gemini_raw':         null,
      'gemini_error':       null,
      'gemini_duration_ms': null,
      'final_intent':       null,
    };

    if (!await file.exists()) {
      debug['gemini_error'] = 'file_not_found';
      Logger.warn('voice_debug', payload: debug,
          feature: 'voice', action: 'process_audio', correlationId: correlationId);
      CorrelationManager.endOperation('voice');
      return const VoiceResult(intent: VoiceIntent.fallback, transcript: '');
    }

    // Lê bytes do arquivo e codifica em base64 para o payload do Gemini.
    final audioBytes  = await file.readAsBytes();
    debug['audio_size_bytes'] = audioBytes.length;

    if (audioBytes.isEmpty) {
      debug['gemini_error'] = 'empty_audio_file';
      Logger.warn('voice_debug', payload: debug,
          feature: 'voice', action: 'process_audio', correlationId: correlationId);
      debugPrint('[VoiceService] Arquivo de áudio vazio — falha na gravação');
      CorrelationManager.endOperation('voice');
      return const VoiceResult(intent: VoiceIntent.fallback, transcript: '');
    }

    final audioBase64 = base64Encode(audioBytes);

    VoiceResult? geminiResult;

    if (AppConstants.geminiApiKey.isNotEmpty) {
      final geminiSw = Stopwatch()..start();
      try {
        final (result, raw, httpStatus) = await _sendAudioToGemini(
          audioBase64,
          existingEnvironments: existingEnvironments,
        );
        geminiResult                   = result;
        debug['gemini_raw']            = raw;
        debug['gemini_http']           = httpStatus;
        debug['gemini_duration_ms']    = geminiSw.elapsedMilliseconds;
      } catch (e, st) {
        debug['gemini_error']       = e.toString();
        debug['gemini_duration_ms'] = geminiSw.elapsedMilliseconds;
        Logger.error('voice_gemini_failed',
            exception: e, stackTrace: st,
            feature: 'voice', action: 'gemini_audio',
            correlationId: correlationId,
            durationMs: geminiSw.elapsedMilliseconds);
        debugPrint('[VoiceService] Gemini Audio erro: $e');
      }
    } else {
      debug['gemini_error'] = 'no_api_key';
    }

    final finalResult = geminiResult ??
        const VoiceResult(intent: VoiceIntent.fallback, transcript: '');

    debug['final_intent'] = finalResult.intent.name;
    Logger.info('voice_debug', payload: debug,
        feature: 'voice', action: 'process_audio', correlationId: correlationId,
        durationMs: debug['gemini_duration_ms'] as int?);
    debugPrint('[VoiceService] voice_debug: $debug');

    CorrelationManager.endOperation('voice');
    return finalResult;
  }

  // Versão simplificada: processa áudio e retorna apenas a transcrição.
  // Usada pelos campos de formulário (nome do ambiente, título do gatilho).
  // Não precisa de existingEnvironments — campos de formulário só transcrevem.
  Future<String?> transcribeAudio(String filePath) async {
    final result = await processAudio(filePath);
    return result.transcript.isNotEmpty ? result.transcript : null;
  }

  // BUG 2 — transcrição PURA para respostas de confirmação (sim/não).
  // Usa prompt MÍNIMO (só transcrever, sem NLU/plano) para NUNCA classificar
  // intenção durante uma confirmação. A decisão continua 100% local em
  // VoiceService.parseYesNo. O app não tem STT on-device, então a transcrição
  // ainda passa pelo Gemini — mas sem o prompt pesado de classificação.
  // Retorna null em erro/rede/áudio vazio (caller trata como "não ouvi").
  Future<String?> transcribeOnly(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    if (AppConstants.geminiApiKey.isEmpty) return null;
    const prompt = 'Transcreva EXATAMENTE o audio em pt-BR. '
        'Responda SO com JSON: {"transcricao":"texto falado"}. Sem markdown.';
    final (raw, status) = await _sendAudioRaw(base64Encode(bytes), prompt);
    if (status != 200 || raw == null) return null;
    try {
      final env = jsonDecode(raw) as Map<String, dynamic>;
      final text = (((env['candidates'] as List?)?.firstOrNull
              as Map?)?['content'] as Map?)?['parts']?[0]?['text'] as String?;
      if (text == null) return null;
      final parsed = jsonDecode(_stripMarkdown(text)) as Map<String, dynamic>;
      final t = (parsed['transcricao'] as String?) ??
          (parsed['transcript'] as String?);
      return (t != null && t.trim().isNotEmpty) ? t.trim() : null;
    } catch (_) {
      return null;
    }
  }

  // ── Fase 2 — assistente: áudio → plano de ações + resposta natural ──────────

  // Envia o áudio ao Gemini com o prompt de ASSISTENTE e devolve um VoicePlanResult
  // (reply + actions + follow_up + context_updates). MANTÉM 1 chamada Gemini por
  // interação (STT + estruturação juntos). [contextSummary] é o trecho de memória
  // de conversa injetado no prompt para resolver referências implícitas.
  // Erros/rede/arquivo vazio → VoicePlanResult.empty() (caller decide o feedback).
  Future<VoicePlanResult> processAudioAsPlan(
    String filePath, {
    List<String> existingEnvironments = const [],
    // Fase 2.1 — IDs paralelos a existingEnvironments (mesma ordem). Regra #1 da
    // sprint: enviar nome + ID ao Gemini para ele decidir reutilizar vs criar.
    List<String> existingEnvironmentIds = const [],
    String contextSummary = '',
  }) async {
    final file = File(filePath);
    final correlationId = CorrelationManager.beginOperation('voice');
    try {
      if (!await file.exists()) return VoicePlanResult.empty();
      final audioBytes = await file.readAsBytes();
      if (audioBytes.isEmpty) return VoicePlanResult.empty();
      if (AppConstants.geminiApiKey.isEmpty) return VoicePlanResult.empty();

      final audioBase64 = base64Encode(audioBytes);
      // Prompt = assistente + ambientes existentes (nome+ID) + data/hora atual +
      // contexto de conversa. _dateTimeContext é reaproveitado por processTextAsPlan.
      final prompt = AppConstants.geminiAssistantPrompt +
          _buildAssistantEnvContext(existingEnvironments, existingEnvironmentIds) +
          _dateTimeContext +
          (contextSummary.isNotEmpty ? '\n$contextSummary' : '');

      final sw = Stopwatch()..start();
      final (raw, status) = await _sendAudioRaw(audioBase64, prompt);
      Logger.info('voice_plan_debug',
          payload: {
            'gemini_http': status,
            'gemini_duration_ms': sw.elapsedMilliseconds,
            'raw_len': raw?.length ?? 0,
          },
          feature: 'voice', action: 'plan',
          correlationId: correlationId, durationMs: sw.elapsedMilliseconds);

      if (status != 200 || raw == null) return VoicePlanResult.empty();
      return _parsePlanResponse(raw);
    } catch (e, st) {
      Logger.error('voice_plan_failed',
          exception: e, stackTrace: st,
          feature: 'voice', action: 'plan', correlationId: correlationId);
      return VoicePlanResult.empty();
    } finally {
      CorrelationManager.endOperation('voice');
    }
  }

  // POST do áudio ao Gemini com um prompt arbitrário; devolve (rawJson, httpStatus).
  // maxOutputTokens elevado (2048) para acomodar planos com várias ações sem
  // truncar. temperature 0.2 permite pequena variação natural no campo reply.
  // CORRECAO 1 (herdada): lê todos os bytes antes de decodificar (evita truncamento).
  Future<(String?, int?)> _sendAudioRaw(String audioBase64, String prompt) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {'inline_data': {'mime_type': 'audio/m4a', 'data': audioBase64}},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 2048},
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      final respBytes  = await consolidateHttpClientResponseBytes(response);
      final raw        = utf8.decode(respBytes);

      if (httpStatus != 200) {
        debugPrint('[VoiceService] plan HTTP $httpStatus: $raw');
        return (null, httpStatus);
      }
      return (raw, httpStatus);
    } finally {
      client.close();
    }
  }

  // Trecho de DATA E HORA ATUAIS (com dia da semana pt-BR) injetado no prompt do
  // assistente. Compartilhado por processAudioAsPlan e processTextAsPlan — o Gemini
  // usa isto para resolver "hoje", "amanha", "segunda que vem", "dia 25", etc.
  String get _dateTimeContext {
    final now = DateTime.now();
    const weekdayNames = ['segunda-feira', 'terca-feira', 'quarta-feira',
        'quinta-feira', 'sexta-feira', 'sabado', 'domingo'];
    return '\nDATA E HORA ATUAIS: ${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} '
        '(${weekdayNames[now.weekday - 1]}). '
        'Use isso para resolver "hoje", "amanha", "essa semana", nomes de dias '
        'da semana e datas relativas.';
  }

  // Espelha processAudioAsPlan(), mas o comando JÁ é texto (sem STT/áudio). Usa o
  // MESMO geminiAssistantPrompt + contexto de ambientes + _dateTimeContext, então
  // aceita qualquer comando (lembrete/ambiente/gatilho), não só lembretes.
  Future<VoicePlanResult> processTextAsPlan(
    String transcript, {
    List<String> existingEnvironments = const [],
    List<String> existingEnvironmentIds = const [],
    String contextSummary = '',
  }) async {
    final correlationId = CorrelationManager.beginOperation('voice_text');
    try {
      if (transcript.trim().isEmpty) return VoicePlanResult.empty();
      if (AppConstants.geminiApiKey.isEmpty) return VoicePlanResult.empty();

      final prompt = AppConstants.geminiAssistantPrompt +
          _buildAssistantEnvContext(existingEnvironments, existingEnvironmentIds) +
          _dateTimeContext +
          (contextSummary.isNotEmpty ? '\n$contextSummary' : '');

      final sw = Stopwatch()..start();
      final (raw, status) = await _sendTextRaw(transcript, prompt);
      Logger.info('text_plan_debug',
          payload: {
            'gemini_http': status,
            'gemini_duration_ms': sw.elapsedMilliseconds,
            'raw_len': raw?.length ?? 0,
          },
          feature: 'voice', action: 'text_plan',
          correlationId: correlationId, durationMs: sw.elapsedMilliseconds);

      if (status != 200 || raw == null) return VoicePlanResult.empty();
      return _parsePlanResponse(raw);
    } catch (e, st) {
      Logger.error('text_plan_failed',
          exception: e, stackTrace: st,
          feature: 'voice', action: 'text_plan', correlationId: correlationId);
      return VoicePlanResult.empty();
    } finally {
      CorrelationManager.endOperation('voice_text');
    }
  }

  // Igual a _sendAudioRaw, mas envia o comando como TEXTO (sem inline_data de
  // áudio). Mesmo endpoint/config. Devolve (rawJson, httpStatus).
  Future<(String?, int?)> _sendTextRaw(String userText, String prompt) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\nComando do usuario: "$userText"'},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 2048},
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      final respBytes  = await consolidateHttpClientResponseBytes(response);
      final raw        = utf8.decode(respBytes);

      if (httpStatus != 200) {
        debugPrint('[VoiceService] text plan HTTP $httpStatus: $raw');
        return (null, httpStatus);
      }
      return (raw, httpStatus);
    } finally {
      client.close();
    }
  }

  // Extrai o texto do envelope Gemini e o converte em VoicePlanResult.
  // Casos especiais:
  //   - texto vazio / JSON inválido → VoicePlanResult.empty();
  //   - resposta no schema antigo (intent, sem actions) → legacyResult preenchido
  //     via _mapGeminiResponse (retrocompatibilidade com a Fase 1).
  VoicePlanResult _parsePlanResponse(String raw) {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    final text = (((envelope['candidates'] as List?)?.firstOrNull
            as Map?)?['content'] as Map?)?['parts']
        ?[0]?['text'] as String?;
    if (text == null || text.trim().isEmpty) return VoicePlanResult.empty();

    final clean = _stripMarkdown(text);
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(clean) as Map<String, dynamic>;
    } catch (e, st) {
      Logger.warn('gemini_plan_json_invalid',
          payload: {'preview': clean.length > 200 ? clean.substring(0, 200) : clean},
          exception: e, stackTrace: st, feature: 'voice', action: 'plan_parse');
      return VoicePlanResult.empty();
    }

    final transcript = (parsed['transcricao'] as String?) ??
        (parsed['transcript'] as String?) ?? '';
    final reply = (parsed['reply'] as String?) ?? '';

    // follow_up "null"/vazio é normalizado para null (não fala pergunta vazia)
    var followUp = parsed['follow_up_question'] as String?;
    if (followUp != null &&
        (followUp.trim().isEmpty || followUp.toLowerCase() == 'null')) {
      followUp = null;
    }

    final ctxUpdates = (parsed['context_updates'] is Map)
        ? Map<String, dynamic>.from(parsed['context_updates'] as Map)
        : <String, dynamic>{};

    final actionsRaw = parsed['actions'];
    final plan = ExecutionPlan.fromJsonList(actionsRaw is List ? actionsRaw : null);

    // Retrocompatibilidade: schema antigo (intent) sem actions → VoiceResult.
    VoiceResult? legacy;
    if (plan.isEmpty && parsed['intent'] != null) {
      legacy = _mapGeminiResponse(parsed);
    }

    return VoicePlanResult(
      transcript:     transcript,
      reply:          reply,
      plan:           plan,
      followUp:       followUp,
      contextUpdates: ctxUpdates,
      legacyResult:   legacy,
    );
  }

  // Processa TEXTO (transcrição corrigida manualmente) via Gemini ou regex.
  // existingEnvironments: injetado no prompt para match exato com banco.
  // Usado pelo botão "Re-analisar" no fallback sheet.
  Future<VoiceResult> resolveIntentFromText(
    String transcript, {
    List<String> existingEnvironments = const [],
  }) async {
    if (transcript.trim().isEmpty) {
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }
    if (AppConstants.geminiApiKey.isNotEmpty) {
      try {
        final geminiResponse = await _sendTextToGemini(
          transcript,
          existingEnvironments: existingEnvironments,
        );
        final result = geminiResponse.$1;
        if (result != null) return result;
      } catch (e) {
        debugPrint('[VoiceService] Gemini Text erro: $e');
      }
    }
    // Fallback: regex offline
    return parseIntent(transcript);
  }

  // Envia áudio em base64 ao Gemini 2.5 Flash com inlineParts.
  // CORRECAO 1: usa consolidateHttpClientResponseBytes em vez de
  // response.transform(utf8.decoder).join() para evitar truncamento em
  // respostas grandes (bug que causava ~80% das falhas de voz).
  // CORRECAO 2: injeta lista de ambientes no prompt via _buildEnvContext().
  // Retorna (VoiceResult?, rawJson, httpStatus).
  Future<(VoiceResult?, String?, int?)> _sendAudioToGemini(
    String audioBase64, {
    List<String> existingEnvironments = const [],
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Prompt com contexto de ambientes para o Gemini retornar nomes exatos
      final fullPrompt =
          AppConstants.geminiSystemPrompt + _buildEnvContext(existingEnvironments);

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': fullPrompt},
              {
                'inline_data': {
                  'mime_type': 'audio/m4a',
                  'data':      audioBase64,
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature':     0,
          'maxOutputTokens': 512,
        },
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      // CORRECAO 1: lê todos os bytes antes de decodificar — evita truncamento
      final respBytes  = await consolidateHttpClientResponseBytes(response);
      final raw        = utf8.decode(respBytes);

      if (httpStatus != 200) {
        debugPrint('[VoiceService] Gemini Audio HTTP $httpStatus: $raw');
        return (null, 'HTTP $httpStatus: $raw', httpStatus);
      }

      return _parseGeminiResponse(raw, httpStatus);
    } finally {
      client.close();
    }
  }

  // Envia TEXTO ao Gemini para re-análise após edição manual da transcrição.
  // CORRECAO 1: mesma correção de leitura de bytes que _sendAudioToGemini.
  // CORRECAO 2: injeta lista de ambientes no prompt.
  Future<(VoiceResult?, String?, int?)> _sendTextToGemini(
    String transcript, {
    List<String> existingEnvironments = const [],
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Prompt de texto com contexto de ambientes
      final fullPrompt =
          AppConstants.geminiTextPrompt + _buildEnvContext(existingEnvironments);

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': fullPrompt},
              {'text': transcript},
            ],
          },
        ],
        'generationConfig': {'temperature': 0, 'maxOutputTokens': 300},
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      // CORRECAO 1: lê todos os bytes antes de decodificar
      final respBytes  = await consolidateHttpClientResponseBytes(response);
      final raw        = utf8.decode(respBytes);

      if (httpStatus != 200) return (null, 'HTTP $httpStatus: $raw', httpStatus);
      return _parseGeminiResponse(raw, httpStatus);
    } finally {
      client.close();
    }
  }

  // Constrói o trecho do prompt que informa ao Gemini quais ambientes existem.
  // Retorna '' se a lista estiver vazia (sem contexto extra = comportamento padrão).
  // O Gemini deve retornar o nome EXATO da lista para evitar erros de match.
  static String _buildEnvContext(List<String> envs) {
    if (envs.isEmpty) return '';
    return '\nAmbientes existentes no banco do usuario: ${envs.join(', ')}.'
        '\nRetorne o nome do ambiente EXATAMENTE como aparece na lista '
        '(sem alterar maiusculas, minusculas ou acentos).';
  }

  // Fase 2.1 — contexto de ambientes para o ASSISTENTE (plano de acoes).
  // Envia NOME + ID de cada ambiente ja cadastrado para o Gemini REUTILIZAR
  // (gerar so create_trigger com o nome exato) em vez de recriar. Regra #1 da
  // sprint. Os IDs sao apenas referencia de identidade: as actions continuam
  // carregando o NOME exato (o executor casa por nome via _matchEnv).
  // Lista vazia -> instrui explicitamente que todo local citado e novo.
  static String _buildAssistantEnvContext(List<String> names, List<String> ids) {
    if (names.isEmpty) {
      return '\nAmbientes existentes: nenhum. Todo local citado e novo '
          '(create_environment antes do create_trigger).';
    }
    final buf = StringBuffer('\nAmbientes existentes (reutilize pelo nome EXATO; '
        'nao recrie os que ja estao aqui):');
    for (var i = 0; i < names.length; i++) {
      final id = i < ids.length ? ids[i] : '';
      buf.write('\n- ${names[i]}${id.isNotEmpty ? ' [id:$id]' : ''}');
    }
    buf.write('\nSe o local dito NAO estiver nesta lista, e novo.');
    return buf.toString();
  }

  // Extrai o texto gerado do envelope Gemini e o converte em VoiceResult.
  // Compartilhado por _sendAudioToGemini e _sendTextToGemini.
  (VoiceResult?, String?, int?) _parseGeminiResponse(String raw, int status) {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    final text = (((envelope['candidates'] as List?)?.firstOrNull
            as Map?)?['content'] as Map?)?['parts']
        ?[0]?['text'] as String?;

    if (text == null || text.trim().isEmpty) {
      return (null, 'empty_candidates', status);
    }

    final clean = _stripMarkdown(text);
    debugPrint('[VoiceService] Gemini resposta limpa: $clean');

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(clean) as Map<String, dynamic>;
    } catch (e, st) {
      Logger.warn('gemini_json_invalid',
          payload: {'preview': clean.length > 200 ? clean.substring(0, 200) : clean},
          exception: e, stackTrace: st, feature: 'voice', action: 'gemini_parse');
      debugPrint('[VoiceService] JSON inválido: $clean');
      return (null, 'invalid_json: $clean', status);
    }

    return (_mapGeminiResponse(parsed), clean, status);
  }

  // Remove blocos de markdown que o modelo pode adicionar por engano.
  static String _stripMarkdown(String text) => text
      .replaceAll(RegExp(r'```[a-zA-Z]*[\r\n]*'), '')
      .replaceAll('```', '')
      .trim();

  // CORRECAO 4: Converte o JSON do Gemini (novo schema) em VoiceResult tipado.
  // Suporta os 7 schemas padronizados definidos em AppConstants.geminiSystemPrompt,
  // com retro-compatibilidade para o schema legado (criar_trigger, criar_ambiente...).
  VoiceResult _mapGeminiResponse(Map<String, dynamic> json) {
    final intentStr   = (json['intent'] as String?) ?? 'unknown';
    // 'transcricao' presente nos schemas novo e legado
    final transcricao = (json['transcricao'] as String?) ?? '';

    switch (intentStr) {

      // ── Schemas novos (V2, padronizados) ──────────────────────────────────

      case 'create_trigger':
        // {"intent":"create_trigger","environment":"nome_exato","trigger":{"title":"","content":""}}
        final trigger = json['trigger'] as Map<String, dynamic>?;
        return VoiceResult(
          intent:          VoiceIntent.createTrigger,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
          triggerAction:   trigger?['title'] as String?,
          triggerContent:  trigger?['content'] as String?,
        );

      case 'create_environment':
        // {"intent":"create_environment","environment":{"name":"","location":"","radius":100}}
        final env     = json['environment'];
        final envName = env is Map ? env['name'] as String? : env as String?;
        final radius  = env is Map ? (env['radius'] as num?)?.toInt() : null;
        return VoiceResult(
          intent:            VoiceIntent.createEnvironment,
          transcript:        transcricao,
          environmentName:   envName,
          environmentRadius: radius,
        );

      case 'create_environment_with_trigger':
        // {"intent":"create_environment_with_trigger","environment":{"name":"","radius":100},"triggers":[{"title":""}]}
        final env      = json['environment'] as Map<String, dynamic>?;
        final rawTriggers = (json['triggers'] as List?)?.cast<Map>() ?? [];
        final titles   = rawTriggers
            .map((t) => (t['title'] as String?) ?? '')
            .where((t) => t.isNotEmpty)
            .toList();
        return VoiceResult(
          intent:            VoiceIntent.createEnvironmentWithTrigger,
          transcript:        transcricao,
          environmentName:   env?['name'] as String?,
          environmentRadius: (env?['radius'] as num?)?.toInt(),
          triggerTitles:     titles,
          // Primeiro gatilho como action principal para snackbars
          triggerAction:     titles.firstOrNull,
        );

      case 'update_environment':
        // {"intent":"update_environment","environment":{"name":"nome_exato","changes":{"radius":200}}}
        final env     = json['environment'] as Map<String, dynamic>?;
        final changes = env?['changes'] as Map<String, dynamic>?;
        return VoiceResult(
          intent:            VoiceIntent.updateEnvironment,
          transcript:        transcricao,
          environmentName:   env?['name'] as String?,
          environmentRadius: (changes?['radius'] as num?)?.toInt(),
        );

      case 'list_environments':
        // {"intent":"list_environments"}
        return VoiceResult(
          intent:     VoiceIntent.listEnvironments,
          transcript: transcricao,
        );

      case 'list_triggers':
        // {"intent":"list_triggers","environment":"nome"}
        return VoiceResult(
          intent:          VoiceIntent.listTriggers,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
        );

      case 'resolve_trigger':
        // {"intent":"resolve_trigger","environment":"nome","trigger_title":"titulo"}
        return VoiceResult(
          intent:          VoiceIntent.resolveTrigger,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
          triggerAction:   json['trigger_title'] as String?,
        );

      // ── Schemas legados (retro-compatibilidade) ────────────────────────────

      case 'criar_trigger':
        return VoiceResult(
          intent:          VoiceIntent.createTrigger,
          transcript:      transcricao,
          environmentName: json['ambiente'] as String?,
          triggerAction:   json['titulo'] as String?,
          triggerContent:  json['conteudo'] as String?,
        );

      case 'criar_ambiente':
        return VoiceResult(
          intent:          VoiceIntent.createEnvironment,
          transcript:      transcricao,
          environmentName: json['ambiente'] as String?,
        );

      case 'resolver_trigger':
        return VoiceResult(
          intent:        VoiceIntent.resolveTrigger,
          transcript:    transcricao,
          triggerAction: json['titulo'] as String?,
        );

      case 'listar_triggers':
        return VoiceResult(
          intent:          VoiceIntent.listTriggers,
          transcript:      transcricao,
          environmentName: json['ambiente'] as String?,
        );

      // ── Schemas de exclusão (V2-VoicePro-Etapa3) ─────────────────────────────

      case 'delete_environment':
        // {"intent":"delete_environment","environment":"nome_exato_do_banco"}
        return VoiceResult(
          intent:          VoiceIntent.deleteEnvironment,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
        );

      case 'delete_trigger':
        // {"intent":"delete_trigger","environment":"nome_ou_null","trigger":{"title":"titulo"}}
        final delTrigger = json['trigger'] as Map<String, dynamic>?;
        return VoiceResult(
          intent:          VoiceIntent.deleteTrigger,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
          triggerAction:   delTrigger?['title'] as String?,
        );

      case 'delete_all_triggers':
        // {"intent":"delete_all_triggers","environment":"nome_exato_do_banco"}
        return VoiceResult(
          intent:          VoiceIntent.deleteAllTriggers,
          transcript:      transcricao,
          environmentName: json['environment'] as String?,
        );

      case 'delete_all_environments':
        // {"intent":"delete_all_environments","transcricao":"texto falado"}
        // Operação global — não carrega environment; a confirmação por voz e a
        // contagem de ambientes são resolvidas na camada de UI (home_screen).
        return VoiceResult(
          intent:     VoiceIntent.deleteAllEnvironments,
          transcript: transcricao,
        );

      default: // 'unknown', 'nao_entendido' e qualquer não reconhecido
        return VoiceResult(
          intent:     VoiceIntent.fallback,
          transcript: transcricao,
        );
    }
  }

  // ── TTS ───────────────────────────────────────────────────────────────────

  // Inicializa TTS com pt-BR. Chamada automática antes de speak().
  Future<void> _initTts() async {
    if (_ttsReady) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsReady = true;
  }

  // Sintetiza [text] em voz. [rate]: 0.1 (muito lenta) a 1.0 (muito rápida).
  // FIX 3: skip se o botão flutuante falou há menos de 10 s — evita TTS duplicado
  // quando o usuário abre o app logo após um comando pelo botão flutuante.
  Future<void> speak(String text, {double rate = 0.5}) async {
    final prefs   = await SharedPreferences.getInstance();
    final spokeAt = prefs.getInt('floating_spoke_at') ?? 0;
    final diffMs  = DateTime.now().millisecondsSinceEpoch - spokeAt;
    if (diffMs < 10000) return; // floating falou há menos de 10 s — não repetir

    await _initTts();
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
    await _tts.speak(text);
  }

  // Para a fala em andamento
  Future<void> stopSpeaking() async => _tts.stop();

  // ── Guardas de Fase 1 (assistente inteligente) ──────────────────────────────

  // Regex que reconhece transcrições "de relógio" que o STT às vezes devolve
  // quando o usuário não fala nada (ex.: "00:00", "0:00", "00.00", "0.00").
  // São tratadas como ausência de fala, nunca como comando.
  static final _clockLikeRegex = RegExp(r'^\s*\d{1,2}[:.]\d{2}\s*$');

  // Regex que verifica se a string contém ao menos uma letra ou dígito "de fala".
  // Usada para rejeitar transcrições compostas apenas de pontuação/espaços.
  static final _hasWordCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  // Decide se uma transcrição deve encerrar o fluxo por "não ouvi você".
  //
  // Objetivo: evitar chamar o Gemini (e evitar abrir qualquer sheet) quando não
  // houve fala real. Retorna true para:
  //   - string vazia ou só espaços;
  //   - padrões de relógio ("00:00", "0:00", "00.00");
  //   - conteúdo apenas de pontuação (sem letra/dígito).
  // O retorno antecipado garante custo zero de rede nesses casos.
  static bool isInvalidTranscript(String? text) {
    if (text == null) return true;
    final t = text.trim();
    if (t.isEmpty) return true;
    if (_clockLikeRegex.hasMatch(t)) return true;
    if (!_hasWordCharRegex.hasMatch(t)) return true; // só pontuação
    return false;
  }

  // Interpreta uma resposta falada de confirmação como sim/não.
  //
  // Fluxo: usado pelo fluxo reutilizável de confirmação por voz. Roda 100% local
  // (regex), portanto NÃO consome chamadas Gemini adicionais além da transcrição.
  // Retorna:
  //   true  → afirmativo (sim, pode, claro, isso, confirmar, quero, manda...);
  //   false → negativo   (não, nao, cancela, deixa, para, negativo...);
  //   null  → ambíguo    (a UI decide re-perguntar ou cancelar por segurança).
  static bool? parseYesNo(String? text) {
    if (text == null) return null;
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return null;
    const yes = ['sim', 'pode', 'claro', 'isso', 'confirmar', 'confirma',
      'quero', 'manda', 'positivo', 'com certeza', 'certo', 'ok', 'okay',
      'aha', 'uhum', 'bora', 'vai', 'exato', 'exatamente', 'afirmativo'];
    const no  = ['não', 'nao', 'cancela', 'cancelar', 'deixa', 'para',
      'negativo', 'nunca', 'jamais', 'nada', 'esquece', 'melhor não',
      'melhor nao'];
    // Negativo tem prioridade: "não pode" deve resolver como não.
    final hasNo  = no.any((w) => t.contains(w));
    if (hasNo) return false;
    final hasYes = yes.any((w) => t.contains(w));
    if (hasYes) return true;
    return null;
  }

  // ── Regex fallback ────────────────────────────────────────────────────────

  // Interpreta texto localmente via regex (sem rede, sem Gemini).
  // Usado quando Gemini indisponível e o usuário corrige a transcrição.
  VoiceResult parseIntent(String transcript) {
    final lower = transcript.toLowerCase().trim();
    if (lower.isEmpty) {
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }

    final createMatch = _regexCreate.firstMatch(lower);
    if (createMatch != null) {
      return VoiceResult(
        intent:          VoiceIntent.createTrigger,
        transcript:      transcript,
        triggerAction:   _capitalize(createMatch.group(1)?.trim() ?? ''),
        environmentName: createMatch.group(2)?.trim(),
      );
    }

    final envMatch = _regexOpenEnv.firstMatch(lower);
    if (envMatch != null) {
      return VoiceResult(
        intent:          VoiceIntent.createEnvironment,
        transcript:      transcript,
        environmentName: _capitalize(envMatch.group(1)?.trim() ?? ''),
      );
    }

    final resolveMatch = _regexResolve.firstMatch(lower);
    if (resolveMatch != null) {
      return VoiceResult(
        intent:        VoiceIntent.resolveTrigger,
        transcript:    transcript,
        triggerAction: resolveMatch.group(1)?.trim(),
      );
    }

    final listMatch = _regexList.firstMatch(lower);
    if (listMatch != null) {
      return VoiceResult(
        intent:          VoiceIntent.listTriggers,
        transcript:      transcript,
        environmentName: listMatch.group(1)?.trim(),
      );
    }

    return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
  }

  // Capitaliza a primeira letra de uma string
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Libera recursos ao descartar o provider (chamado pelo onDispose do Riverpod)
  void dispose() {
    _cancelAutoStopTimers();
    _autoStopController.close();
    _recorder.dispose();
    _tts.stop();
  }
}
