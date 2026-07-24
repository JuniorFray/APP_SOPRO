import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// Utilitário de seleção/armazenamento da foto do pin POR AMBIENTE.
//
// A imagem escolhida pela galeria é COPIADA para o diretório de documentos do
// app (path_provider) com nome único por ambiente — o path original da galeria
// pode ser revogado pelo Android. A imagem nunca vai para servidor (on-device).
class PinImageStore {
  PinImageStore._();

  static final ImagePicker _picker = ImagePicker();

  // Abre a galeria, copia a imagem escolhida para o diretório do app e retorna
  // o novo caminho. Retorna null se o usuário cancelar. Remove o arquivo antigo
  // ([previousPath]) para não acumular órfãos ao trocar a foto.
  static Future<String?> pickForEnvironment(
    String envId, {
    String? previousPath,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return null; // usuário cancelou

    final dir = await getApplicationDocumentsDirectory();
    // Timestamp no nome evita cache antigo (do File e do sprite do MapLibre).
    final dest =
        '${dir.path}/pin_env_${envId}_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(picked.path).copy(dest);

    await _deleteQuietly(previousPath);
    return dest;
  }

  // Remove o arquivo da foto (ao "Remover imagem"). Silencioso se já não existe.
  static Future<void> remove(String? path) => _deleteQuietly(path);

  static Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Falha ao apagar arquivo antigo é inofensiva — ignora.
    }
  }
}
