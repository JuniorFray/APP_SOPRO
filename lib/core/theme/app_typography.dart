import 'package:flutter/material.dart';

/// Métricas tipográficas do Sopro — V2 Premium.
/// Inspirado no ecossistema Apple: tracking negativo em títulos,
/// line-height generoso em corpo, hierarquia visual clara.
/// Contém APENAS: fontSize, fontWeight, height, letterSpacing, fontFamily.
/// Cor é responsabilidade do widget via .copyWith(color: ...).
abstract final class AppTypography {
  // ── Títulos ────────────────────────────────────────────────────────────────

  /// 22sp w700 -0.5 — AppBar, cabeçalhos principais.
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// 18sp w700 -0.3 — títulos de sheet/dialog.
  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// 15sp w600 -0.1 — títulos de item de lista, linhas de configuração.
  static const TextStyle titleSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  // ── Labels ─────────────────────────────────────────────────────────────────

  /// 13sp w600 0.2 — subcabeçalhos de seção.
  static const TextStyle labelLarge = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// 11sp w700 1.0 — cabeçalhos de seção em maiúsculas.
  static const TextStyle labelMedium = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.0,
  );

  /// 10sp w500 — badges, chips, rótulos menores.
  static const TextStyle labelSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.3,
  );

  // ── Body ───────────────────────────────────────────────────────────────────

  /// 14sp h1.5 — corpo de texto, subtítulos, itens de dropdown.
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.1,
  );

  /// 13sp h1.45 — texto secundário, hints de campo.
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0.1,
  );

  // ── Especiais ──────────────────────────────────────────────────────────────

  /// 11sp h1.3 — contadores, helperText, rótulos finos.
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// 12sp monospace — coordenadas geográficas, valores técnicos.
  static const TextStyle monospace = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
    height: 1.4,
  );
}
