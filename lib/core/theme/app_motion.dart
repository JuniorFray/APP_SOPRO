import 'package:flutter/material.dart';

/// Durações e curvas de animação do Sopro — V2 Premium.
abstract final class AppMotion {
  // ── Durações ───────────────────────────────────────────────────────────────

  /// Press/scale de botão: reação imediata ao toque.
  static const Duration micro = Duration(milliseconds: 80);

  /// Focus state e feedback de campo: rápido mas perceptível.
  static const Duration quick = Duration(milliseconds: 120);

  /// Transições rápidas de UI: dots, AnimatedSize, chips.
  static const Duration fast = Duration(milliseconds: 200);

  /// Transição de página do PageView no onboarding.
  static const Duration page = Duration(milliseconds: 350);

  /// Animação de pulso repeat-reverse do FAB de voz.
  static const Duration fabPulse = Duration(milliseconds: 700);

  /// Exibição do estado de erro do FAB antes de retornar ao idle.
  static const Duration brief = Duration(milliseconds: 800);

  /// Exibição do checkmark de sucesso do FAB.
  static const Duration success = Duration(seconds: 1);

  // ── Curvas ─────────────────────────────────────────────────────────────────

  /// Saída cúbica: snappy, para press/scale de botão.
  static const Curve snap = Curves.easeOutCubic;

  /// Easing padrão: entrada e saída equilibradas.
  static const Curve standard = Curves.easeInOut;

  /// Desaceleração: elementos chegando à posição final.
  static const Curve decelerate = Curves.easeOut;

  /// Spring: retorno elástico suave após interação.
  static const Curve spring = Curves.easeOutBack;
}
