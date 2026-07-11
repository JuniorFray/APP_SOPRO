// app_theme.dart — Fachada de retrocompatibilidade do Design System Sopro.
//
// Todas as telas continuam importando AppTheme sem nenhuma modificação.
// Os valores delegam para os tokens centralizados (AppColors, AppRadius)
// e o ThemeData delega para SoproTheme.darkTheme — fonte única de verdade.
//
// IMPORTANTE: não adicionar novos valores aqui.
// Novos widgets devem importar AppColors, AppRadius, AppTypography, etc. diretamente.

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'sopro_theme.dart';

class AppTheme {
  AppTheme._();

  // ── Fundos ────────────────────────────────────────────────────────────────
  static const Color backgroundPrimary  = AppColors.backgroundPrimary;
  static const Color backgroundSurface  = AppColors.backgroundSurface;
  static const Color backgroundElevated = AppColors.backgroundElevated;

  // ── Ações ─────────────────────────────────────────────────────────────────
  static const Color accent   = AppColors.accent;
  static const Color success  = AppColors.success;
  static const Color warning  = AppColors.warning;

  // ── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textDisabled  = AppColors.textDisabled;

  // ── Bordas ────────────────────────────────────────────────────────────────
  static const Color borderColor = AppColors.border;

  // ── Raios de borda ────────────────────────────────────────────────────────
  static const double radiusCard   = AppRadius.card;
  static const double radiusButton = AppRadius.button;
  static const double radiusInput  = AppRadius.input;
  static const double radiusBadge  = AppRadius.badge;
  static const double radiusIcon   = AppRadius.icon;

  // ── Decoração de card ─────────────────────────────────────────────────────
  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
    color: color ?? AppColors.backgroundCard,
    borderRadius: BorderRadius.circular(AppRadius.card),
    border: Border.all(color: AppColors.border, width: 0.5),
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => SoproTheme.darkTheme;
}
