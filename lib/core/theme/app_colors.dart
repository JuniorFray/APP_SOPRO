import 'package:flutter/material.dart';

/// Paleta de cores do Sopro — V2 Premium.
/// Nenhum widget deve declarar Color() diretamente — referenciar aqui.
abstract final class AppColors {
  // ── Fundos (sistema de profundidade em 4 camadas) ─────────────────────────
  static const Color backgroundPrimary       = Color(0xFF101014); // scaffold
  static const Color backgroundSurface       = Color(0xFF171821); // painéis, AppBar
  static const Color backgroundCard          = Color(0xFF1D1F2B); // cards
  static const Color backgroundCardHighlight = Color(0xFF222438); // topo do gradiente do card
  static const Color backgroundInput         = Color(0xFF202334); // campos de texto
  static const Color backgroundElevated      = Color(0xFF252535); // popovers, dropdowns

  // ── Ação primária ─────────────────────────────────────────────────────────
  static const Color accent    = Color(0xFFF04B67); // primary CTA
  static const Color secondary = Color(0xFFFF6A88); // hover / gradiente de botão
  static const Color accentPurple = Color(0xFF8D6BFF); // accent complementar (Fase 5B)

  // ── Semântica ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF32D296);
  static const Color warning = Color(0xFFF6B94A);
  static const Color danger  = Color(0xFFFF5B5B);

  // ── FAB de voz ────────────────────────────────────────────────────────────
  static const Color fabSuccessDark   = Color(0xFF1E7A4A);
  static const Color fabGlowIdle      = Color(0x4DF04B67); // accent 30%
  static const Color fabGlowRecording = Color(0x80FF5B5B); // danger 50%

  // ── Feedback (snackbars) ──────────────────────────────────────────────────
  static const Color snackbarSuccess = Color(0xFF1B6B3A);
  static const Color snackbarDanger  = Color(0xFFBF2E2E);

  // ── Ícones de onboarding ──────────────────────────────────────────────────
  static const Color onboardingLocation     = Color(0xFF4CAF50);
  static const Color onboardingNotification = Color(0xFFFFA726);
  static const Color onboardingBle          = Color(0xFF42A5F5);

  // ── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF); // contraste máximo AA
  static const Color textSecondary = Color(0xFFA2A6B8); // textos de apoio
  static const Color textDisabled  = Color(0xFF6D7285); // placeholders, contadores

  // ── Bordas ────────────────────────────────────────────────────────────────
  static const Color border         = Color(0xFF272A3A); // borda padrão
  static const Color borderHighlight = Color(0xFF3A3D52); // borda de destaque / inner glow
}
