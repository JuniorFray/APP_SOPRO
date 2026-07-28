// Estágio Sherpa (teste, só Home): STT 100% offline via Whisper base int8.
//
// Isolado de propósito — NÃO integra com o resto do app ainda. Só carrega o
// modelo dos assets e expõe transcribe(wavPath). O caminho antigo
// (speech_to_text) segue intacto; a troca acontece no Estágio 4 por flag.
//
// sherpa_onnx lê o modelo de um CAMINHO DE ARQUIVO, não de asset direto. Por
// isso, na 1ª execução copiamos os 3 arquivos do bundle para um diretório
// gravável do app (getApplicationSupportDirectory) e reusamos daí em diante.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// Roda o decode do Whisper (CPU-bound) numa isolate SEPARADA — igual ao TTS,
// senão a transcrição trava a UI. OfflineRecognizer não é enviável entre
// isolates, mas a memória nativa é do processo: passamos só o ENDEREÇO do
// ponteiro, reconstruímos via fromPtr aqui e devolvemos o texto (sendable).
// readWave + createStream + decode + getResult acontecem todos nesta isolate.
// DEBUG TIMING: retorno agora carrega (texto, readWavMs, decodeMs) medidos DENTRO
// da isolate p/ o caller logar STT_READ_WAV_MS / STT_DECODE_MS. Remover depois.
(String, int, int) _decodeInIsolate(int recognizerAddr, String wavFilePath) {
  sherpa.initBindings(); // bindings são por-isolate
  final rec = sherpa.OfflineRecognizer.fromPtr(
    ptr: Pointer.fromAddress(recognizerAddr).cast(),
    config: const sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(tokens: ''),
    ),
  );
  final swRead = Stopwatch()..start(); // DEBUG TIMING
  final wave = sherpa.readWave(wavFilePath);
  final readWavMs = swRead.elapsedMilliseconds; // DEBUG TIMING
  if (wave.samples.isEmpty) return ('', readWavMs, 0); // DEBUG TIMING
  final stream = rec.createStream();
  try {
    final swDecode = Stopwatch()..start(); // DEBUG TIMING
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    rec.decode(stream);
    final text = rec.getResult(stream).text.trim();
    final decodeMs = swDecode.elapsedMilliseconds; // DEBUG TIMING
    return (text, readWavMs, decodeMs); // DEBUG TIMING
  } finally {
    stream.free(); // libera o stream nativo sempre
  }
}

class SherpaSttService {
  // Pasta e arquivos do modelo dentro de assets/ (declarados no pubspec).
  // Whisper SMALL int8: substituiu o base, que errava comandos curtos em pt
  // ("criar ambiente casa" -> "criarem bem em de casa"). Small acerta
  // (confirmado na CLI oficial com o mesmo áudio do device).
  static const _assetDir = 'assets/models/whisper_small';
  static const _encoder = 'small-encoder.int8.onnx';
  static const _decoder = 'small-decoder.int8.onnx';
  static const _tokens = 'small-tokens.txt';

  // Reconhecedor nativo — criado uma única vez (lazy) e reutilizado.
  sherpa.OfflineRecognizer? _recognizer;
  // Serializa a inicialização: chamadas concorrentes esperam o mesmo Future.
  Future<void>? _initFuture;
  int _lastModelLoadMs = 0; // DEBUG TIMING — duração do último _init (model load)

  // Garante bindings nativos + modelo carregado. Idempotente.
  Future<void> _ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    final swLoad = Stopwatch()..start(); // DEBUG TIMING
    // Carrega a lib nativa (libsherpa-onnx-c-api.so no Android). Chamar 1x só;
    // reinvocar é inofensivo, mas guardamos via _initFuture mesmo assim.
    sherpa.initBindings();

    // Copia os assets para o disco gravável (só se ainda não existirem).
    final dir = await getApplicationSupportDirectory();
    final destDir = p.join(dir.path, 'sherpa', 'whisper_small');
    final encPath = await _copyAsset(_encoder, destDir);
    final decPath = await _copyAsset(_decoder, destDir);
    final tokPath = await _copyAsset(_tokens, destDir);

    // Whisper base é MULTILÍNGUE: fixamos language='pt' + task='transcribe'
    // para forçar português no reconhecimento local — é justamente o que o
    // caminho online do speech_to_text errava (revertia pro inglês, issue #569).
    final model = sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: encPath,
        decoder: decPath,
        language: 'pt',
        task: 'transcribe',
      ),
      tokens: tokPath,
      numThreads: 3, // 3 threads: menor STT_DECODE_MS no SD680 (bench Moto G52);
                     // deixa 1 núcleo Gold livre p/ UI/áudio. 4 threads regride
                     // (contenção com Silver/eficiência). Ver bench Etapa 5.
      debug: false,
      modelType: 'whisper',
    );

    _recognizer =
        sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(model: model));
    _lastModelLoadMs = swLoad.elapsedMilliseconds; // DEBUG TIMING
  }

  // Copia um arquivo de asset para [destDir] se ainda não estiver lá.
  // Retorna o caminho absoluto do arquivo no disco.
  Future<String> _copyAsset(String name, String destDir) async {
    await Directory(destDir).create(recursive: true);
    final dest = File(p.join(destDir, name));
    if (!await dest.exists()) {
      final data = await rootBundle.load('$_assetDir/$name');
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return dest.path;
  }

  // Transcreve um arquivo WAV (mono, PCM; idealmente 16 kHz) para texto pt-BR.
  // Retorna '' quando o áudio não pôde ser lido/decodificado ou nada foi dito.
  // O decode roda em isolate separada — a UI não trava durante a transcrição.
  Future<String> transcribe(String wavFilePath) async {
    final swTotal = Stopwatch()..start();   // DEBUG TIMING
    final cold = _recognizer == null;       // DEBUG TIMING — 1ª vez = model load
    await _ensureReady();
    if (cold) debugPrint('[SOPROPERF] STT_MODEL_LOAD_MS=$_lastModelLoadMs'); // DEBUG TIMING
    final rec = _recognizer;
    if (rec == null) return '';

    final addr = rec.ptr.address; // só o endereço cruza para a isolate
    try {
      final (text, readWavMs, decodeMs) =
          await Isolate.run(() => _decodeInIsolate(addr, wavFilePath)); // DEBUG TIMING
      // DEBUG TIMING — medições individuais do STT. Remover depois.
      debugPrint('[SOPROPERF] STT_READ_WAV_MS=$readWavMs');
      debugPrint('[SOPROPERF] STT_DECODE_MS=$decodeMs');
      debugPrint('[SOPROPERF] STT_TOTAL_MS=${swTotal.elapsedMilliseconds}');
      return text;
    } catch (e) {
      debugPrint('[SherpaSTT] Falha na transcrição: $e');
      return '';
    }
  }

  // Libera o reconhecedor nativo. Chamar ao descartar o serviço.
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _initFuture = null;
  }
}
