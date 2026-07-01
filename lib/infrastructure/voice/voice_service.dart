import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Intenções de voz reconhecidas por regex on-device.
// Nenhum áudio ou texto é enviado a servidores externos.
enum VoiceIntent {
  // "lembra de X quando eu chegar em Y"
  createTrigger,
  // "salva esse lugar como X" / "cria um ambiente chamado X"
  openEnvironment,
  // "resolvi X" / "pode apagar X"
  resolveTrigger,
  // "o que tenho pendente em X?"
  listTriggers,
  // texto livre não classificado
  fallback,
}

// Resultado do processamento de intenção de voz.
class VoiceResult {
  final VoiceIntent intent;
  final String transcript;
  // Ação / título do gatilho (createTrigger, resolveTrigger)
  final String? triggerAction;
  // Nome do ambiente extraído (createTrigger, openEnvironment, listTriggers)
  final String? environmentName;

  const VoiceResult({
    required this.intent,
    required this.transcript,
    this.triggerAction,
    this.environmentName,
  });
}

// Gerencia reconhecimento de fala (STT) e síntese de voz (TTS) on-device.
// Processamento de intenção por regex — sem chamadas a IA ou cloud NLP.
class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;

  // ── Padrões regex para português brasileiro ────────────────────────────────

  // "lembra de [ação] quando eu chegar em [ambiente]"
  static final _regexCreate = RegExp(
    r'lembr[ae](?:[-\s]me)?(?:\s+de)?\s+(.+?)\s+quando\s+(?:eu\s+)?chegar?\s+(?:em|no|na|ao|à|nos|nas)\s+(.+)',
  );

  // "salva esse lugar como [nome]" / "cria um ambiente aqui chamado [nome]"
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

  // Inicializa o engine de reconhecimento. Retorna false se não disponível.
  Future<bool> initStt() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onError:  (e) => debugPrint('[VoiceService] STT erro: ${e.errorMsg}'),
      onStatus: (s) => debugPrint('[VoiceService] STT status: $s'),
    );
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
        if (result.finalResult) {
          onFinal(result.recognizedWords);
        } else {
          onPartial(result.recognizedWords);
        }
      },
      onSoundLevelChange: onSoundLevel,
      localeId:           'pt_BR',
      listenFor:          listenFor,
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        listenMode:    ListenMode.confirmation,
      ),
    );
    return true;
  }

  Future<void> stopListening() async => _stt.stop();

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

  // Sintetiza texto. [rate]: 0.1 (muito lenta) a 1.0 (muito rápida).
  Future<void> speak(String text, {double rate = 0.5}) async {
    await _initTts();
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async => _tts.stop();

  // ── Processamento de intenção ─────────────────────────────────────────────

  // Interpreta a transcrição e retorna a intenção detectada com parâmetros extraídos.
  // Processamento local via regex — determinístico, sem latência de rede.
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

  // Capitaliza a primeira letra da string
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Libera recursos ao descartar o provider
  void dispose() {
    _stt.stop();
    _tts.stop();
  }
}
