import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/core/logger.dart';

// Política única de inicialização do FloatingVoiceService.
//
// Todos os pontos que iniciam o serviço devem chamar [tryStart].
// Nenhum outro código pode invocar startFloatingVoiceService diretamente.
//
// Responsabilidades:
//   • Ler floating_voice_enabled das prefs (o chamador persiste antes de tryStart).
//   • Verificar hasOverlayPermission via MethodChannel.
//   • Verificar (e opcionalmente solicitar) hasMicrophonePermission via MethodChannel.
//   • Registrar service_start_validation_begin / success / failed.
//   • Invocar startFloatingVoiceService somente quando todos os pré-requisitos passam.
//
// O chamador decide se reverte a pref em caso de falha.
class FloatingVoiceServiceManager {
  FloatingVoiceServiceManager._();

  static const _channel = MethodChannel('com.sopro.sopro/overlay');

  // Valida todos os pré-requisitos e inicia o FloatingVoiceService.
  //
  // O chamador deve persistir floating_voice_enabled = true em SharedPreferences
  // ANTES de chamar este método. Em caso de falha, o chamador reverte a pref.
  //
  // [requestPermissionsIfNeeded]: quando true, exibe o diálogo de RECORD_AUDIO
  // se ainda não concedido. Passe true apenas em fluxos explicitamente iniciados
  // pelo usuário (ex: toggle nas Configurações).
  //
  // Retorna null em sucesso; retorna uma chave de motivo em falha:
  //   'floating_voice_disabled' — pref não está marcada como true
  //   'overlay_denied'          — SYSTEM_ALERT_WINDOW não concedida
  //   'record_audio_denied'     — RECORD_AUDIO não concedida (e não solicitada/negada)
  static Future<String?> tryStart({bool requestPermissionsIfNeeded = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final floatingEnabled = prefs.getBool('floating_voice_enabled') ?? false;
    final hasOverlay =
        await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    bool hasMic =
        await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;

    if (!hasMic && requestPermissionsIfNeeded) {
      hasMic =
          await _channel.invokeMethod<bool>('requestMicrophonePermission') ??
              false;
    }

    Logger.info(
      'service_start_validation_begin',
      feature: 'floating_voice',
      action: 'tryStart',
      payload: {
        'floating_voice_enabled': floatingEnabled.toString(),
        'overlay': hasOverlay.toString(),
        'record_audio': hasMic.toString(),
        'sdk': 'dart_layer',
      },
    );

    final String? reason;
    if (!floatingEnabled) {
      reason = 'floating_voice_disabled';
    } else if (!hasOverlay) {
      reason = 'overlay_denied';
    } else if (!hasMic) {
      reason = 'record_audio_denied';
    } else {
      reason = null;
    }

    if (reason != null) {
      Logger.warn(
        'service_start_validation_failed',
        feature: 'floating_voice',
        action: 'tryStart',
        payload: {
          'reason': reason,
          'floating_voice_enabled': floatingEnabled.toString(),
          'overlay': hasOverlay.toString(),
          'record_audio': hasMic.toString(),
          'sdk': 'dart_layer',
        },
      );
      return reason;
    }

    Logger.info(
      'service_start_validation_success',
      feature: 'floating_voice',
      action: 'tryStart',
      payload: {
        'floating_voice_enabled': floatingEnabled.toString(),
        'overlay': hasOverlay.toString(),
        'record_audio': hasMic.toString(),
        'sdk': 'dart_layer',
      },
    );

    await _channel.invokeMethod<void>('startFloatingVoiceService');
    return null;
  }

  // Para o FloatingVoiceService. O chamador é responsável por atualizar
  // a pref floating_voice_enabled e o provider Riverpod.
  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stopFloatingVoiceService');
  }
}
