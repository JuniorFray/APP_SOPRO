import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/voice/voice_service.dart';

// Instância singleton do VoiceService — compartilhado em toda a app.
// Inicializado sob demanda na primeira chamada a startListening() ou speak().
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService();
  // Cancela sessão ativa e libera recursos ao descartar o provider
  ref.onDispose(service.dispose);
  return service;
});

// Toggle de resposta em áudio (TTS) ao processar intenção de voz.
// Quando true, Sopro fala a confirmação da ação reconhecida.
// Persistência: SharedPreferences 'voice_audio_response'.
final voiceAudioResponseProvider = StateProvider<bool>((ref) => true);

// Toggle de resposta em texto ao processar intenção de voz.
// Quando true, exibe a confirmação da ação na UI (além do TTS).
// Persistência: SharedPreferences 'voice_text_response'.
final voiceTextResponseProvider = StateProvider<bool>((ref) => true);

// Velocidade de síntese de voz (TTS).
// 0.3 = Lenta, 0.5 = Normal (padrão), 0.7 = Rápida.
// Persistência: SharedPreferences 'voice_speech_rate'.
final voiceSpeechRateProvider = StateProvider<double>((ref) => 0.5);
