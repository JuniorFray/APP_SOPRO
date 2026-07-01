import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:sopro/core/constants/app_constants.dart';
import 'package:sopro/infrastructure/logging/app_logger.dart';

// Intenções de voz que o app sabe executar.
enum VoiceIntent {
  // "lembra de X quando eu chegar em Y"
  createTrigger,
  // "salva esse lugar como X" / "cria um ambiente chamado X"
  openEnvironment,
  // "resolvi X" / "pode apagar X"
  resolveTrigger,
  // "o que tenho pendente em X?"
  listTriggers,
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
  // Nome do ambiente extraído do comando
  final String? environmentName;

  const VoiceResult({
    required this.intent,
    required this.transcript,
    this.triggerAction,
    this.environmentName,
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

  // Inicia gravação em arquivo temporário (AAC/M4A, 16 kHz, 64 kbps).
  // Configurações reduzidas para minimizar tamanho do payload enviado ao Gemini.
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

      await _recorder.start(
        const RecordConfig(
          encoder:    AudioEncoder.aacLc, // M4A/AAC compatível com Gemini
          bitRate:    64000,              // 64 kbps suficiente para voz
          sampleRate: 16000,             // 16 kHz = padrão para STT
        ),
        path: path,
      );
      return true;
    } catch (e) {
      debugPrint('[VoiceService] Erro ao iniciar gravação: $e');
      return false;
    }
  }

  // Para a gravação e retorna o caminho do arquivo gerado.
  // Retorna null se a gravação não estava ativa ou ocorreu erro.
  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint('[VoiceService] Erro ao parar gravação: $e');
      return null;
    }
  }

  // Cancela a gravação sem processar (usuário descartou).
  Future<void> cancelRecording() async {
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
  // Loga 'voice_debug' no Supabase com: audio_size_bytes, model_used,
  // gemini_http, gemini_raw (resposta bruta), gemini_error e final_intent.
  Future<VoiceResult> processAudio(String filePath) async {
    final file = File(filePath);

    // Mapa de diagnóstico logado no Supabase ao final.
    // model_used confirma qual endpoint foi chamado (diagnóstico de 404).
    // audio_size_bytes=0 indica falha na gravação, não na API.
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
    // audio_size_bytes=0 significa que o AudioRecorder não gravou nada —
    // investigar permissão de microfone ou problema no pacote record.
    final audioBytes  = await file.readAsBytes();
    debug['audio_size_bytes'] = audioBytes.length;

    if (audioBytes.isEmpty) {
      // Arquivo existe mas está vazio: falha na gravação, não na API
      debug['gemini_error'] = 'empty_audio_file';
      AppLogger.log('voice_debug', debug);
      debugPrint('[VoiceService] Arquivo de áudio vazio — falha na gravação');
      return const VoiceResult(intent: VoiceIntent.fallback, transcript: '');
    }

    final audioBase64 = base64Encode(audioBytes);

    VoiceResult? geminiResult;

    if (AppConstants.geminiApiKey.isNotEmpty) {
      try {
        final (result, raw, httpStatus) =
            await _sendAudioToGemini(audioBase64);
        geminiResult        = result;
        debug['gemini_raw'] = raw;
        debug['gemini_http']= httpStatus;
      } catch (e) {
        debug['gemini_error'] = e.toString();
        debugPrint('[VoiceService] Gemini Audio erro: $e');
      }
    } else {
      // Chave não configurada — informa no diagnóstico
      debug['gemini_error'] = 'no_api_key';
    }

    // Fallback: VoiceResult vazio (usuário pode digitar manualmente)
    final finalResult = geminiResult ??
        const VoiceResult(intent: VoiceIntent.fallback, transcript: '');

    debug['final_intent'] = finalResult.intent.name;
    AppLogger.log('voice_debug', debug);
    debugPrint('[VoiceService] voice_debug: $debug');

    return finalResult;
  }

  // Versão simplificada: processa áudio e retorna apenas a transcrição.
  // Usada pelos campos de formulário (nome do ambiente, título do gatilho).
  Future<String?> transcribeAudio(String filePath) async {
    final result = await processAudio(filePath);
    // Retorna null se transcrição vazia (Gemini indisponível ou sem chave)
    return result.transcript.isNotEmpty ? result.transcript : null;
  }

  // Processa TEXTO (transcrição corrigida manualmente) via Gemini ou regex.
  // Usado pelo botão "Re-analisar" no bottom sheet de resultado.
  Future<VoiceResult> resolveIntentFromText(String transcript) async {
    if (transcript.trim().isEmpty) {
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }
    // Tenta Gemini text API se chave disponível
    if (AppConstants.geminiApiKey.isNotEmpty) {
      try {
        // Acessa só o primeiro campo do record — raw e httpStatus descartados
        final geminiResponse = await _sendTextToGemini(transcript);
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
  // Retorna (VoiceResult?, rawJson, httpStatus).
  Future<(VoiceResult?, String?, int?)> _sendAudioToGemini(
    String audioBase64,
  ) async {
    final client = HttpClient();
    // Timeout maior que text API — áudio é payload grande
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
              // Instrução de sistema: define contrato JSON de resposta
              {'text': AppConstants.geminiSystemPrompt},
              // Áudio inline em base64 — Gemini transcreve e classifica
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
          'temperature':     0,    // determinístico para JSON consistente
          'maxOutputTokens': 256,
        },
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      final raw        = await response.transform(utf8.decoder).join();

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
  // Usa geminiTextPrompt (sem instrução de áudio) e timeout menor.
  Future<(VoiceResult?, String?, int?)> _sendTextToGemini(
    String transcript,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

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
              {'text': AppConstants.geminiTextPrompt},
              {'text': transcript},
            ],
          },
        ],
        'generationConfig': {'temperature': 0, 'maxOutputTokens': 200},
      });

      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response   = await request.close();
      final httpStatus = response.statusCode;
      final raw        = await response.transform(utf8.decoder).join();

      if (httpStatus != 200) return (null, 'HTTP $httpStatus: $raw', httpStatus);
      return _parseGeminiResponse(raw, httpStatus);
    } finally {
      client.close();
    }
  }

  // Extrai o texto gerado do envelope Gemini e o converte em VoiceResult.
  // Compartilhado por _sendAudioToGemini e _sendTextToGemini.
  (VoiceResult?, String?, int?) _parseGeminiResponse(String raw, int status) {
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    // Navega: candidates[0].content.parts[0].text
    final text = (((envelope['candidates'] as List?)?.firstOrNull
            as Map?)?['content'] as Map?)?['parts']
        ?[0]?['text'] as String?;

    if (text == null || text.trim().isEmpty) {
      return (null, 'empty_candidates', status);
    }

    // Remove blocos markdown (```json ... ```) que o modelo pode adicionar
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

  // Converte o JSON do Gemini em VoiceResult tipado.
  VoiceResult _mapGeminiResponse(Map<String, dynamic> json) {
    final intentStr   = (json['intent']      as String?) ?? 'nao_entendido';
    // transcricao: o que o Gemini entendeu que o usuário disse
    final transcricao = (json['transcricao'] as String?) ?? '';
    final ambiente    =  json['ambiente']    as String?;
    final titulo      =  json['titulo']      as String?;

    final VoiceIntent intent;
    switch (intentStr) {
      case 'criar_trigger':    intent = VoiceIntent.createTrigger;
      case 'criar_ambiente':   intent = VoiceIntent.openEnvironment;
      case 'resolver_trigger': intent = VoiceIntent.resolveTrigger;
      case 'listar_triggers':  intent = VoiceIntent.listTriggers;
      default:                 intent = VoiceIntent.fallback;
    }

    return VoiceResult(
      intent:          intent,
      transcript:      transcricao,  // transcrição do Gemini
      triggerAction:   titulo,
      environmentName: ambiente,
    );
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
        intent:          VoiceIntent.openEnvironment,
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
    _recorder.dispose();
    _tts.stop();
  }
}
