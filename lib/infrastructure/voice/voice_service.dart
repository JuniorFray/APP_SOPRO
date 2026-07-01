import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
// ou se geminiApiKey estiver vazio em AppConstants.
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
      debugPrint('[VoiceService] pt-BR não encontrado. Locales: '
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
      debugPrint('[VoiceService] Locale pt-BR detectado: $_ptBrLocaleId');
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

  // Detecta se o transcript provavelmente foi capturado em inglês pelo STT.
  // Heurística conservadora: retorna true somente se NÃO houver nenhum
  // indicador claro de português (acentos, palavras comuns).
  // False positives são aceitáveis — o pior caso é enviar contexto extra
  // para o Gemini desnecessariamente.
  bool _mightBeEnglish(String transcript) {
    final lower = transcript.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // Presença de acento ou cedilha = texto claramente em português
    if (lower.contains(RegExp(r'[áéíóúãõâêôàçü]'))) return false;

    // Palavras funcionais portuguesas que dificilmente aparecem em inglês
    const ptMarkers = {
      'de', 'em', 'no', 'na', 'para', 'quando', 'eu', 'você', 'que',
      'um', 'uma', 'com', 'por', 'isso', 'esse', 'essa', 'aqui', 'ali',
      'lembra', 'criar', 'cria', 'salva', 'apaga', 'resolvi', 'tenho',
      'casa', 'trabalho', 'escola', 'mercado', 'obra', 'lugar', 'ambiente',
      'gatilho', 'lembrete', 'pendente', 'fazer',
    };
    for (final word in lower.split(RegExp(r'\s+'))) {
      if (ptMarkers.contains(word)) return false;
    }

    // Nenhum marcador de português encontrado → suspeita de inglês
    return true;
  }

  // Ponto de entrada principal para processar uma transcrição.
  // 1. Detecta se o STT capturou em inglês (heurística).
  // 2. Tenta Gemini API se geminiApiKey estiver configurado.
  // 3. Faz fallback para regex local se Gemini falhar ou sem internet.
  // 4. Loga um evento 'voice_debug' no Supabase com todo o diagnóstico.
  Future<VoiceResult> resolveIntent(String transcript) async {
    // Detecta possível captura em inglês antes de qualquer processamento
    final maybeEnglish = _mightBeEnglish(transcript);

    // Mapa de diagnóstico — preenchido ao longo do fluxo e logado no final
    final debug = <String, dynamic>{
      'transcript':     transcript,
      // Não logamos a chave em si — apenas se está preenchida (true/false)
      'has_key':        AppConstants.geminiApiKey.isNotEmpty,
      'locale_used':    _ptBrLocaleId ?? 'system_default',
      // true se a heurística detectou possível inglês
      'maybe_english':  maybeEnglish,
      'gemini_called':  false,
      'gemini_http':    null,  // status HTTP da chamada Gemini
      'gemini_raw':     null,  // texto bruto retornado pelo modelo
      'gemini_error':   null,  // mensagem de erro, se houve
      'final_intent':   null,  // nome do enum VoiceIntent escolhido
      'environment':    null,
      'trigger_action': null,
    };

    // Sem texto não há o que processar
    if (transcript.trim().isEmpty) {
      debug['final_intent'] = 'fallback_empty';
      AppLogger.log('voice_debug', debug);
      return VoiceResult(intent: VoiceIntent.fallback, transcript: transcript);
    }

    VoiceResult? geminiResult;

    // Tenta Gemini apenas se a chave estiver preenchida
    if (AppConstants.geminiApiKey.isNotEmpty) {
      debug['gemini_called'] = true;
      try {
        // Passa maybeEnglish para que o Gemini receba contexto extra se necessário
        final (result, raw, httpStatus) =
            await _processIntentWithGemini(transcript, maybeEnglish: maybeEnglish);
        geminiResult          = result;
        debug['gemini_raw']   = raw;
        debug['gemini_http']  = httpStatus;
      } catch (e) {
        // Gemini falhou (sem internet, timeout, etc.) → usa regex
        debug['gemini_error'] = e.toString();
        debugPrint('[VoiceService] Gemini indisponível: $e');
      }
    }

    // Fallback para regex se Gemini não retornou resultado válido
    final finalResult = geminiResult ?? parseIntent(transcript);

    // Preenche campos de diagnóstico com o resultado final
    debug['final_intent']   = finalResult.intent.name;
    debug['environment']    = finalResult.environmentName;
    debug['trigger_action'] = finalResult.triggerAction;

    // Log de diagnóstico no Supabase (fire-and-forget, nunca bloqueia UI)
    AppLogger.log('voice_debug', debug);
    debugPrint('[VoiceService] voice_debug: $debug');

    return finalResult;
  }

  // Nota injetada no prompt quando o STT provavelmente capturou em inglês.
  // Exemplos ajudam o Gemini a correlacionar sons ingleses com intenções pt-BR.
  static const _englishHint =
      '\n\n[NOTA DO SISTEMA: O reconhecimento de voz pode ter transcrito em '
      'inglês palavras faladas em português. Interprete a intenção como se '
      'fosse português brasileiro falado em voz alta. Exemplos de erros comuns: '
      '"create" → "criar", "environment" → "ambiente", "trigger" → "gatilho", '
      '"remember" → "lembra", "creative cousin" → "criar ambiente casa", '
      '"solve" → "resolvi". Tente identificar a intenção real mesmo com texto em inglês.]';

  // Envia a transcrição ao Gemini e interpreta a resposta JSON.
  // [maybeEnglish]: se true, injeta _englishHint no prompt para STT em inglês.
  // Retorna um record (VoiceResult?, String? rawText, int? httpStatus).
  // VoiceResult é null se a resposta for inválida ou a chamada falhar.
  Future<(VoiceResult?, String?, int?)> _processIntentWithGemini(
    String transcript, {
    bool maybeEnglish = false,
  }) async {
    final client = HttpClient();
    // Timeout de 8 s — latência típica do Gemini Flash é ~300-500 ms
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      // Monta a URL com a chave de API no query string (padrão Google AI)
      final uri = Uri.parse(
        '${AppConstants.geminiEndpoint}?key=${AppConstants.geminiApiKey}',
      );

      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Se provavelmente capturado em inglês, adiciona nota ao texto do usuário
      // para que o Gemini tente interpretar a intenção correta em pt-BR
      final userText = maybeEnglish ? '$transcript$_englishHint' : transcript;

      // Corpo da requisição: system prompt + transcrição do usuário
      final body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              // System prompt define o contrato de resposta JSON
              {'text': AppConstants.geminiSystemPrompt},
              // Transcrição real (com nota de inglês se detectado)
              {'text': userText},
            ],
          },
        ],
        // Temperatura 0 = determinístico, sem criatividade — queremos JSON exato
        'generationConfig': {
          'temperature':     0,
          'maxOutputTokens': 200,
        },
      });

      // Define Content-Length explicitamente (necessário para dart:io)
      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final httpStatus = response.statusCode;

      // Lê o corpo completo da resposta
      final raw = await response.transform(utf8.decoder).join();

      // Status diferente de 200 = erro da API (cota, chave inválida, etc.)
      if (httpStatus != 200) {
        debugPrint('[VoiceService] Gemini HTTP $httpStatus: $raw');
        // Retorna (null, raw para diagnóstico, httpStatus)
        return (null, 'HTTP $httpStatus: $raw', httpStatus);
      }

      // Decodifica o envelope externo do Gemini
      final envelope = jsonDecode(raw) as Map<String, dynamic>;

      // Navega pela estrutura: candidates[0].content.parts[0].text
      final text = (((envelope['candidates'] as List?)?.firstOrNull
              as Map?)?['content'] as Map?)?['parts']
          ?[0]?['text'] as String?;

      if (text == null || text.trim().isEmpty) {
        return (null, 'empty_candidates', httpStatus);
      }

      // Remove marcadores markdown que o modelo pode adicionar por engano
      // Ex.: ```json\n{"intent":...}\n``` → {"intent":...}
      final clean = _stripMarkdown(text);
      debugPrint('[VoiceService] Gemini texto limpo: $clean');

      // Decodifica o JSON interno (objeto de intenção)
      final Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(clean) as Map<String, dynamic>;
      } catch (e) {
        // Modelo retornou algo que não é JSON — fallback para regex
        debugPrint('[VoiceService] JSON inválido da Gemini: $clean');
        return (null, 'invalid_json: $clean', httpStatus);
      }

      // Converte o objeto JSON para VoiceResult tipado
      final result = _mapGeminiResponse(parsed, transcript);
      return (result, clean, httpStatus);
    } finally {
      // Fecha o HttpClient em qualquer caso (sucesso ou erro)
      client.close();
    }
  }

  // Remove blocos de markdown de código que o modelo pode adicionar.
  // Trata variações: ```json, ```JSON, ```, com ou sem quebra de linha.
  static String _stripMarkdown(String text) {
    return text
        // Remove abertura de bloco (```json, ```JSON, ``` etc.)
        .replaceAll(RegExp(r'```[a-zA-Z]*[\r\n]*'), '')
        // Remove fechamento de bloco (```)
        .replaceAll('```', '')
        // Remove espaços e quebras de linha desnecessárias
        .trim();
  }

  // Converte o objeto JSON retornado pelo Gemini em VoiceResult tipado.
  // [json]: mapa com chaves 'intent', 'ambiente', 'titulo', 'conteudo'.
  // [transcript]: transcrição original para preservar no resultado.
  VoiceResult _mapGeminiResponse(
    Map<String, dynamic> json,
    String transcript,
  ) {
    // Valor padrão 'nao_entendido' se a chave estiver ausente
    final intentStr = (json['intent'] as String?) ?? 'nao_entendido';
    final ambiente  = json['ambiente'] as String?;
    final titulo    = json['titulo']   as String?;

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
