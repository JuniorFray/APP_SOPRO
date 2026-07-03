import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:sopro/core/constants/app_constants.dart';
import 'package:sopro/infrastructure/logging/app_logger.dart';

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
  // Encerra automaticamente após 10 s (maxDuration) ou 1500 ms de silêncio.
  // Retorna true se a gravação iniciou com sucesso.
  Future<bool> startRecording() async {
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

      await _recorder.start(
        const RecordConfig(
          encoder:    AudioEncoder.aacLc, // M4A/AAC compatível com Gemini
          bitRate:    12000,              // 12 kbps — voz inteligível, arquivo minúsculo
          sampleRate: 8000,              // 8 kHz = qualidade telefônica, ok para STT
        ),
        path: path,
      );

      // Timer de duração máxima: 10 s
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(
        const Duration(seconds: 10),
        () => _fireAutoStop('max_duration'),
      );

      // Detecção de silêncio: amplitude abaixo de -35 dBFS por 1500 ms → auto-stop.
      // Separa silêncio genuíno (fim da fala) de pausas curtas naturais.
      _silenceTimer?.cancel();
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (amp.current < -35.0) {
          // Silêncio detectado — inicia (ou mantém) o timer de silêncio
          _silenceTimer ??= Timer(
            const Duration(milliseconds: 1500),
            () => _fireAutoStop('silence'),
          );
        } else {
          // Som detectado — cancela o timer de silêncio (não é fim de fala)
          _silenceTimer?.cancel();
          _silenceTimer = null;
        }
      });

      return true;
    } catch (e) {
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
    } catch (e) {
      debugPrint('[VoiceService] Erro ao parar gravação: $e');
      return null;
    }
  }

  // Cancela a gravação sem processar (usuário descartou ou arrastou para cima).
  Future<void> cancelRecording() async {
    _cancelAutoStopTimers();
    try {
      await _recorder.cancel();
    } catch (e) {
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

    // Mapa de diagnóstico logado no Supabase ao final.
    final debug = <String, dynamic>{
      'audio_size_bytes': 0,
      'model_used':       AppConstants.geminiModel,
      'gemini_http':      null,
      'gemini_raw':       null,
      'gemini_error':     null,
      'final_intent':     null,
    };

    if (!await file.exists()) {
      debug['gemini_error'] = 'file_not_found';
      AppLogger.log('voice_debug', debug);
      return const VoiceResult(intent: VoiceIntent.fallback, transcript: '');
    }

    // Lê bytes do arquivo e codifica em base64 para o payload do Gemini.
    final audioBytes  = await file.readAsBytes();
    debug['audio_size_bytes'] = audioBytes.length;

    if (audioBytes.isEmpty) {
      debug['gemini_error'] = 'empty_audio_file';
      AppLogger.log('voice_debug', debug);
      debugPrint('[VoiceService] Arquivo de áudio vazio — falha na gravação');
      return const VoiceResult(intent: VoiceIntent.fallback, transcript: '');
    }

    final audioBase64 = base64Encode(audioBytes);

    VoiceResult? geminiResult;

    if (AppConstants.geminiApiKey.isNotEmpty) {
      try {
        final (result, raw, httpStatus) = await _sendAudioToGemini(
          audioBase64,
          existingEnvironments: existingEnvironments,
        );
        geminiResult        = result;
        debug['gemini_raw'] = raw;
        debug['gemini_http']= httpStatus;
      } catch (e) {
        debug['gemini_error'] = e.toString();
        debugPrint('[VoiceService] Gemini Audio erro: $e');
      }
    } else {
      debug['gemini_error'] = 'no_api_key';
    }

    final finalResult = geminiResult ??
        const VoiceResult(intent: VoiceIntent.fallback, transcript: '');

    debug['final_intent'] = finalResult.intent.name;
    AppLogger.log('voice_debug', debug);
    debugPrint('[VoiceService] voice_debug: $debug');

    return finalResult;
  }

  // Versão simplificada: processa áudio e retorna apenas a transcrição.
  // Usada pelos campos de formulário (nome do ambiente, título do gatilho).
  // Não precisa de existingEnvironments — campos de formulário só transcrevem.
  Future<String?> transcribeAudio(String filePath) async {
    final result = await processAudio(filePath);
    return result.transcript.isNotEmpty ? result.transcript : null;
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
    } catch (_) {
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
  Future<void> speak(String text, {double rate = 0.5}) async {
    await _initTts();
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
    await _tts.speak(text);
  }

  // Para a fala em andamento
  Future<void> stopSpeaking() async => _tts.stop();

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
