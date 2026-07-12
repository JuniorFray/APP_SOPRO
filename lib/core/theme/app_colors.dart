import 'package:flutter/material.dart';

/// Paleta de cores do Sopro — Dark Glass V3.1.
/// Nenhum widget deve declarar Color() diretamente — referenciar aqui.
abstract final class AppColors {
  // ── Fundos — Dark Glass ───────────────────────────────────────────────────
  static const Color backgroundPrimary       = Color(0xFF090D18); // scaffold
  static const Color backgroundSurface       = Color(0xFF0B1220); // painéis, AppBar
  static const Color backgroundCard          = Color(0xFF0F1A32); // glass base opaco
  static const Color backgroundCardHighlight = Color(0xFF142240); // brilho do topo do card
  static const Color backgroundInput         = Color(0xFF111A30); // campos de texto
  static const Color backgroundElevated      = Color(0xFF0F1828); // popovers, dropdowns

  // ── Accent — Azul ─────────────────────────────────────────────────────────
  static const Color accent       = Color(0xFF4F8CFF); // primary CTA
  static const Color secondary    = Color(0xFF7CB3FF); // accent glow / gradiente de botão
  static const Color accentPurple = Color(0xFF8D6BFF); // accent complementar

  // ── Semântica ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF32D296);
  static const Color warning = Color(0xFFF6B94A);
  static const Color danger  = Color(0xFFFF5B5B);

  // ── FAB de voz ────────────────────────────────────────────────────────────
  static const Color fabSuccessDark   = Color(0xFF1E7A4A);
  static const Color fabPinkStart     = Color(0xFFFF6B82); // idle gradient start
  static const Color fabPinkEnd       = Color(0xFFF04566); // idle gradient end
  static const Color fabGlowIdle      = Color(0x33FF6B82); // pink 20%
  static const Color fabGlowRecording = Color(0x4DFF5B5B); // danger 30%

  // ── AppBar buttons ────────────────────────────────────────────────────────
  static const Color appBarButtonBg   = Color(0xFF182033);
  static const Color appBarButtonIcon = Color(0xFFD8E2FF);

  // ── Feedback (snackbars) ──────────────────────────────────────────────────
  static const Color snackbarSuccess = Color(0xFF1B6B3A);
  static const Color snackbarDanger  = Color(0xFFBF2E2E);

  // ── Ícones de onboarding ──────────────────────────────────────────────────
  static const Color onboardingLocation     = Color(0xFF4CAF50);
  static const Color onboardingNotification = Color(0xFFFFA726);
  static const Color onboardingBle          = Color(0xFF42A5F5);

  // ── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB7C0D6);
  static const Color textDisabled  = Color(0xFF7E879C);

  // ── Bordas — Glass (branco translúcido) ───────────────────────────────────
  static const Color border         = Color(0x14FFFFFF); // white 8%
  static const Color borderHighlight = Color(0x28FFFFFF); // white 16%
}
