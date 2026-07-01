import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:sopro/core/constants/app_constants.dart';

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
  // texto não classificado — fallback para gatilho manual
  fallback,
}

// Resultado do processamento de intenção de voz.
class VoiceResult {
  // Intenção detectada (enum)
  final VoiceIntent intent;
  // Texto original transcrito pelo STT
  final String transcript;
  // Título/ação do gatilho (createTrigger, resolveTrigger)
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

// Gerencia reconhecimento de fala (STT) e síntese de voz (TTS) on-device.
// Processamento primário via Gemini API; fallback para regex local se offline
// ou se GEMINI_API_KEY estiver vazio.
class VoiceService {
  // Engine de reconhecimento de fala (on-device)
  final _stt = SpeechToText();
  // Engine de síntese de voz (on-device)
  final _tts = FlutterTts();
  // Flag para evitar múltiplas inicializações do STT
  bool _sttReady = false;
  // Flag para evitar múltiplas inicializações do TTS
  bool _ttsReady = false;
  // Locale exato pt-BR detectado no dispositivo (ex.: 'pt_BR', 'por-BRA').
  // null = não encontrado → STT usa locale padrão do sistema.
  String? _ptBrLocaleId;

  // ── Padrões regex para português brasileiro ────────────────────────────────
  // Usados como fallback quando Gemini não está disponível.

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

  // ── STT ───────────────────────────────────────────────────────────────────

  // Procura o locale pt-BR entre os disponíveis no dispositivo.
  // Ordem de preferência: 'pt_BR' → 'pt-BR' → qualquer um começando com 'pt'.
  Future<void> _findPtBrLocale() async {
    try {
      // locales() lista os locales instalados no motor STT do dispositivo
      final locales = await _stt.locales();
      // Tentativa 1: match exato com underline (padrão Android)
      for (final loc in locales) {
        if (loc.localeId == 'pt_BR') { _ptBrLocaleId = loc.localeId; return; }
      }
      // Tentativa 2: match exato com hífen (padrão iOS / alguns Android)
      for (final loc in locales) {
        if (loc.localeId == 'pt-BR') { _ptBrLocaleId = loc.localeId; return; }
      }
      // Tentativa 3: qualquer locale que comece com 'pt' (pt_PT, por-BRA, etc.)
      for (final loc in locales) {
        if (loc.localeId.toLowerCase().startsWith('pt')) {
          _ptBrLocaleId = loc.localeId;
          return;
        }
      }
      // Nenhum locale português encontrado → usa padrão do sistema
      debugPrint('[VoiceService] pt-BR não encontrado. Locales disponíveis: '
          '${locales.map((l) => l.localeId).join(', ')}');
    } catch (e) {
      // Falha silenciosa — localeId null faz o STT usar o padrão do sistema
      debugPrint('[VoiceService] Erro ao listar locales: $e');
    }
  }

  // Inicializa o engine de reconhecimento e detecta o locale pt-BR.
  // Retorna false se STT não estiver disponível no dispositivo.
  Future<bool> initStt() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onError:  (e) => debugPrint('[VoiceService] STT erro: ${e.errorMsg}'),
      onStatus: (s) => debugPrint('[VoiceService] STT status: $s'),
    );
    if (_sttReady) {
      // Detecta locale pt-BR uma única vez após inicialização bem-sucedida
      await _findPtBrLocale();
      debugPrint('[VoiceService] Locale pt-BR: $_ptBrLocaleId');
    }
    return _sttReady;
  }

  // Inicia escuta com callbacks para resultados parciais, finais e nível de som.
  // [listenFor]: duração máxima de escuta (padrão: 10 s).
  // Retorna true se o engine foi iniciado com sucesso.
  Future<bool> startListening({
    required void Function(String partial) onPartial,
    required void Function(String final_) onFinal,
    void Function(double level)? onSoundLevel,
    Duration listenFor = const Duration(seconds: 10),
  }) async {
    final ok = await initStt();
    if (!ok) return false;

    // Garante que nenhuma sessão anterior está ativa
    if (_stt.isListening) await _stt.stop();

    await _stt.listen(
      onResult: (result) {
        // Separa resultado parcial (transcrição em tempo real) do final
        if (result.finalResult) {
          onFinal(result.recognizedWords);
        } else {
          onPartial(result.recognizedWords);
        }
      },
      onSoundLevelChange: onSoundLevel,
      // Locale detectado em _findPtBrLocale(); null = padrão do sistema
      localeId:           _ptBrLocaleId,
      listenFor:          listenFor,
      listenOptions: SpeechListenOptions(
        // Cancela se ocorrer erro de rede/permissão durante a escuta
        cancelOnError: true,
        // confirmation: espera silêncio para confirmar fim da fala
        listenMode:    ListenMode.confirmation,
      ),
    );
    return true;
  }

  // Para a escuta imediatamente (chamado ao fechar o sheet ou ao parar manualmente)
  Future<void> stopListening() async => _stt.stop();

  // true enquanto o engine está escutando ativamente
  bool get isListening => _stt.isListening;

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

  // ── Processamento de intenção ─────────────────────────────────────────────

  // Ponto de entrada principal para processar uma transcrição.
  // 1. Tenta Gemini API se a chave estiver configurada.
  // 2. Faz fallback para regex local se Gemini falhar ou não houver internet.
  Future<VoiceResult> resolveIntent(String transcript) async {
    // Sem texto não há o que processar
    if (transcript.trim().isEmpty) {
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }

    // Tenta Gemini apenas se a chave estiver preenchida
    if (AppConstants.geminiApiKey.isNotEmpty) {
      try {
        final geminiResult = await _processIntentWithGemini(transcript);
        if (geminiResult != null) return geminiResult;
      } catch (e) {
        // Gemini falhou (sem internet, cota excedida, etc.) → usa regex
        debugPrint('[VoiceService] Gemini indisponível, usando regex: $e');
      }
    }

    // Fallback: regex on-device, determinístico e offline
    return parseIntent(transcript);
  }

  // Envia a transcrição ao Gemini Flash Lite e interpreta a resposta JSON.
  // Retorna null se a resposta for inválida ou a chamada falhar.
  Future<VoiceResult?> _processIntentWithGemini(String transcript) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      // Monta a URL com a chave de API no query string (padrão Google AI)
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );

      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Corpo da requisição: system prompt + transcrição do usuário
      final body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              // O system prompt ensina o modelo o contrato de resposta JSON
              {'text': AppConstants.geminiSystemPrompt},
              // Transcrição real do usuário que o modelo deve classificar
              {'text': transcript},
            ],
          },
        ],
        // Configuração de geração: temperatura 0 = determinístico / sem criatividade
        'generationConfig': {
          'temperature': 0,
          'maxOutputTokens': 128,
        },
      });

      request.write(body);
      final response = await request.close();

      // Qualquer status diferente de 200 é tratado como falha
      if (response.statusCode != 200) {
        debugPrint('[VoiceService] Gemini HTTP ${response.statusCode}');
        return null;
      }

      // Lê o corpo da resposta e decodifica o JSON externo (envelope Gemini)
      final raw = await response.transform(utf8.decoder).join();
      final envelope = jsonDecode(raw) as Map<String, dynamic>;

      // Extrai o texto gerado dentro do envelope padrão da API Gemini
      final text = (((envelope['candidates'] as List?)?.firstOrNull
              as Map?)?['content'] as Map?)?['parts']
          ?[0]?['text'] as String?;

      if (text == null || text.trim().isEmpty) return null;

      // Remove possíveis blocos markdown que o modelo pode adicionar por engano
      final clean = text.replaceAll(RegExp(r'```[a-z]*\n?|```'), '').trim();

      // Decodifica o JSON interno (objeto de intenção)
      final Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(clean) as Map<String, dynamic>;
      } catch (_) {
        // Gemini retornou algo que não é JSON — ignora e vai para regex
        debugPrint('[VoiceService] Gemini resposta não-JSON: $clean');
        return null;
      }

      // Converte o objeto JSON para VoiceResult
      return _mapGeminiResponse(parsed, transcript);
    } finally {
      // Fecha o cliente HTTP em qualquer caso (sucesso ou erro)
      client.close();
    }
  }

  // Converte o objeto JSON retornado pelo Gemini em VoiceResult tipado.
  // [json]: mapa com chaves 'intent', 'ambiente', 'titulo', 'conteudo'.
  // [transcript]: transcrição original para preservar no resultado.
  VoiceResult _mapGeminiResponse(Map<String, dynamic> json, String transcript) {
    // Valor padrão 'nao_entendido' se a chave estiver ausente
    final intentStr     = (json['intent']   as String?) ?? 'nao_entendido';
    final ambiente      = json['ambiente']  as String?;
    final titulo        = json['titulo']    as String?;

    // Mapeamento das strings de intenção do Gemini para o enum local
    final VoiceIntent intent;
    switch (intentStr) {
      case 'criar_trigger':
        intent = VoiceIntent.createTrigger;
      case 'criar_ambiente':
        intent = VoiceIntent.openEnvironment;
      case 'resolver_trigger':
        intent = VoiceIntent.resolveTrigger;
      case 'listar_triggers':
        intent = VoiceIntent.listTriggers;
      default:
        // 'nao_entendido' ou qualquer string desconhecida → fallback
        intent = VoiceIntent.fallback;
    }

    return VoiceResult(
      intent:          intent,
      transcript:      transcript,
      // titulo do Gemini → triggerAction (ação a executar ou desativar)
      triggerAction:   titulo,
      // ambiente do Gemini → environmentName (nome do local)
      environmentName: ambiente,
    );
  }

  // Interpreta a transcrição localmente via regex (sem rede).
  // Determinístico e preciso para as frases pré-definidas.
  VoiceResult parseIntent(String transcript) {
    final lower = transcript.toLowerCase().trim();
    if (lower.isEmpty) {
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }

    // Testa cada padrão na ordem de especificidade (mais específico primeiro)
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

    // Nenhum padrão casou → intenção desconhecida
    return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
  }

  // Capitaliza a primeira letra (ex.: 'falar com joao' → 'Falar com joao')
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Libera recursos ao descartar o provider (chamado pelo onDispose do Riverpod)
  void dispose() {
    _stt.stop();
    _tts.stop();
  }
}
