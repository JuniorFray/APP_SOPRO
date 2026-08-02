import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

// Fonte UNICA de texto do assistente de voz: prompt de plano + frases de persona.
// O MESMO arquivo (assets/voice/voice_content.json) e lido pelo Home (aqui, via
// rootBundle) e pelo overlay nativo (Kotlin, via AssetManager) — sem duplicar o
// texto em cada lado. Carregado uma vez em main() por [load]; os getters de
// AppConstants (prompt) e AssistantPersona (frases) leem deste cache.
class VoiceContent {
  VoiceContent._(); // namespace estatico

  static Map<String, dynamic>? _plan;
  static Map<String, dynamic>? _persona;

  // Le e cacheia o asset. Idempotente — chamadas repetidas nao reprocessam.
  static Future<void> load() async {
    if (_plan != null) return;
    final raw = await rootBundle.loadString('assets/voice/voice_content.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _plan = (json['plan'] as Map).cast<String, dynamic>();
    _persona = (json['persona'] as Map).cast<String, dynamic>();
  }

  // Segmento do prompt de plano por chave (vazio se ausente/nao carregado).
  static String plan(String key) => _plan?[key] as String? ?? '';

  // Frase de persona por chave (com {placeholders} ainda por resolver no getter).
  static String persona(String key) => _persona?[key] as String? ?? '';
}
