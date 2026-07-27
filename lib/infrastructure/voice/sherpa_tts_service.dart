// Estágio Sherpa (teste, só Home): TTS 100% offline via Piper VITS pt_BR-miro-high.
//
// Isolado — não integra com o resto ainda. flutter_tts segue intacto; a troca
// vem no Estágio 4 por flag. sherpa gera SAMPLES (não toca áudio): escrevemos um
// WAV temporário e reproduzimos com audioplayers.
//
// Igual ao STT: sherpa lê de CAMINHO de arquivo, então na 1ª execução copiamos
// os assets (modelo, tokens e a árvore espeak-ng-data inteira, exigida pelo
// Piper) do bundle para um diretório gravável.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// Roda a síntese (CPU-bound) numa isolate SEPARADA para não travar a UI.
// O objeto nativo OfflineTts vive na main isolate e NÃO é enviável entre
// isolates — mas a memória nativa é do processo inteiro. Passamos só o
// ENDEREÇO do ponteiro (int), reconstruímos o wrapper aqui via fromPtr e
// chamamos generate(). Retornamos (samples, sampleRate), ambos sendable.
// A config passada ao fromPtr é descartável: generate() só usa o ptr.
(Float32List, int) _generateInIsolate(int ttsAddr, String text) {
  sherpa.initBindings(); // bindings são por-isolate: inicializa nesta também
  final tts = sherpa.OfflineTts.fromPtr(
    ptr: Pointer.fromAddress(ttsAddr).cast(),
    config: const sherpa.OfflineTtsConfig(model: sherpa.OfflineTtsModelConfig()),
  );
  final audio = tts.generate(text: text, sid: 0, speed: 1.0);
  return (audio.samples, audio.sampleRate);
}

class SherpaTtsService {
  // Raiz dos assets do modelo (declarada no pubspec).
  // Voz faber-medium: substituiu miro-high, cujo tarball/export gerava ruído
  // (confirmado na CLI oficial sherpa-onnx com os mesmos arquivos).
  static const _assetRoot = 'assets/models/piper_pt_br_faber';
  static const _modelFile = 'pt_BR-faber-medium.onnx';
  static const _tokensFile = 'tokens.txt';
  static const _espeakDirName = 'espeak-ng-data';

  final _player = AudioPlayer();

  sherpa.OfflineTts? _tts;
  Future<void>? _initFuture;

  Future<void> _ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    sherpa.initBindings();

    final dir = await getApplicationSupportDirectory();
    final destRoot = p.join(dir.path, 'sherpa', 'piper_pt_br_faber');

    // Modelo + tokens (arquivos soltos na raiz).
    final modelPath = await _copyAsset('$_assetRoot/$_modelFile',
        p.join(destRoot, _modelFile));
    final tokensPath = await _copyAsset('$_assetRoot/$_tokensFile',
        p.join(destRoot, _tokensFile));
    // Árvore espeak-ng-data (dezenas de subpastas) — copiada preservando a
    // hierarquia. dataDir aponta para a pasta raiz dela no disco.
    final espeakDest = p.join(destRoot, _espeakDirName);
    await _copyAssetTree('$_assetRoot/$_espeakDirName/', espeakDest);

    // Piper = VITS + dataDir apontando para espeak-ng-data (fonemização).
    final model = sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: modelPath,
        tokens: tokensPath,
        dataDir: espeakDest,
      ),
      numThreads: 2,
      debug: false,
    );
    _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: model));
  }

  // Copia um único asset para [destPath] se ainda não existir. Retorna o caminho.
  Future<String> _copyAsset(String assetPath, String destPath) async {
    final dest = File(destPath);
    if (!await dest.exists()) {
      await dest.parent.create(recursive: true);
      final data = await rootBundle.load(assetPath);
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return dest.path;
  }

  // Copia todos os assets sob [assetPrefix] para [destRoot], espelhando a
  // hierarquia. Usa o AssetManifest para enumerar (asset dir não é listável
  // via API de arquivo — só o manifesto sabe quais assets foram empacotados).
  Future<void> _copyAssetTree(String assetPrefix, String destRoot) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest.listAssets().where((a) => a.startsWith(assetPrefix));
    for (final asset in assets) {
      final rel = asset.substring(assetPrefix.length); // caminho relativo
      await _copyAsset(asset, p.join(destRoot, rel));
    }
  }

  // Sintetiza [text] em pt-BR (voz miro-high) e reproduz. Aguarda o fim da fala.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureReady();
    final tts = _tts;
    if (tts == null) return;

    // Síntese CPU-bound → isolate separada (sid=0 voz única, speed=1.0 natural).
    // Passa só o endereço do ponteiro nativo; a UI segue fluida durante a fala.
    final addr = tts.ptr.address;
    final (Float32List samples, int sampleRate) =
        await Isolate.run(() => _generateInIsolate(addr, text));
    if (samples.isEmpty) {
      debugPrint('[SherpaTTS] Geração vazia para: "$text"');
      return;
    }

    // Escreve WAV temporário e toca. writeWave retorna false em falha de I/O.
    final wavPath = p.join((await getTemporaryDirectory()).path, 'sherpa_tts.wav');
    final ok = sherpa.writeWave(
      filename: wavPath,
      samples: samples,
      sampleRate: sampleRate,
    );
    if (!ok) {
      debugPrint('[SherpaTTS] Falha ao escrever WAV');
      return;
    }

    // INSTRUMENTAÇÃO (temporária): copia o mesmo WAV para uma pasta puxável via
    // adb pull, sobrescrevendo a cada fala. Não altera o playback abaixo.
    // Falha aqui é ignorada — nunca deve derrubar a reprodução.
    try {
      final ext = await getExternalStorageDirectory(); // .../Android/data/<pkg>/files
      if (ext != null) {
        final debugPath = p.join(ext.path, 'sherpa_tts_debug.wav');
        await File(wavPath).copy(debugPath);
        debugPrint('[SherpaTTS] WAV debug salvo em: $debugPath');
      } else {
        debugPrint('[SherpaTTS] getExternalStorageDirectory() = null (sem debug WAV)');
      }
    } catch (e) {
      debugPrint('[SherpaTTS] Falha ao salvar WAV debug: $e');
    }

    await _player.stop(); // interrompe fala anterior, se houver
    await _player.play(DeviceFileSource(wavPath));
    // Aguarda terminar de tocar para o Future refletir o fim real da fala.
    await _player.onPlayerComplete.first;
  }

  // Interrompe a fala em andamento.
  Future<void> stop() => _player.stop();

  // Libera recursos nativos + player.
  void dispose() {
    _tts?.free();
    _tts = null;
    _initFuture = null;
    _player.dispose();
  }
}
