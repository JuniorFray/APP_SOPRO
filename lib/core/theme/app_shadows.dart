import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Sombras do Sopro — V2 Premium.
/// Difusas, suaves. Sem sombra Android antiga.
abstract final class AppShadows {
  // ── Cards ─────────────────────────────────────────────────────────────────

  /// Sombra padrão de card: suave, difusa, mínimo spread.
  static const BoxShadow card = BoxShadow(
    color: Color(0x1A000000),
    blurRadius: 20,
    spreadRadius: 0,
    offset: Offset(0, 6),
  );

  /// Sombra mais intensa para cards em foco / hover.
  static const BoxShadow cardElevated = BoxShadow(
    color: Color(0x26000000),
    blurRadius: 32,
    spreadRadius: 0,
    offset: Offset(0, 10),
  );

  // ── FAB de voz ────────────────────────────────────────────────────────────

  /// Glow do FAB em estado idle (accent 30%).
  static const BoxShadow fabIdle = BoxShadow(
    color: AppColors.fabGlowIdle,
    blurRadius: 16,
    spreadRadius: 2,
  );

  /// Glow do FAB durante gravação (danger 50%, mais intenso).
  static const BoxShadow fabRecording = BoxShadow(
    color: AppColors.fabGlowRecording,
    blurRadius: 22,
    spreadRadius: 4,
  );

  // ── Busca de endereço ─────────────────────────────────────────────────────

  /// Sombra da lista de resultados de busca.
  static const BoxShadow searchResults = BoxShadow(
    color: Color(0x33000000),
    blurRadius: 12,
    spreadRadius: 0,
    offset: Offset(0, 4),
  );
}
