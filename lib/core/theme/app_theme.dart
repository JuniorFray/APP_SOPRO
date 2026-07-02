// app_theme.dart — Design System "Soft Dark" do Sopro (Sprint V2-VoicePro Etapa 2)
// Centraliza cores, raios, bordas e tipografia.
// NUNCA use valores hardcoded em widgets — use sempre AppTheme.

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Fundos ────────────────────────────────────────────────────────────────
  static const Color backgroundPrimary  = Color(0xFF12121A); // camada base
  static const Color backgroundSurface  = Color(0xFF1E1E2A); // cards e listas
  static const Color backgroundElevated = Color(0xFF252535); // sheets e modais

  // ── Ações ─────────────────────────────────────────────────────────────────
  static const Color accent   = Color(0xFFE8445A); // CTA e urgência
  static const Color success  = Color(0xFF0F9B58); // gatilho resolvido
  static const Color warning  = Color(0xFFF5A623); // gatilho pendente

  // ── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF8A8A9A);
  static const Color textDisabled  = Color(0xFF3A3A4A);

  // ── Bordas ────────────────────────────────────────────────────────────────
  // 0.5 dp em todos os cards para separação sutil sem peso visual
  static const Color borderColor = Color(0xFF2A2A38);

  // ── Raios de borda ────────────────────────────────────────────────────────
  static const double radiusCard   = 16; // cards e containers principais
  static const double radiusButton = 20; // botões (pílula suave)
  static const double radiusInput  = 14; // campos de texto / inputs
  static const double radiusBadge  = 20; // badges / chips / pills
  static const double radiusIcon   = 12; // container de ícone de ambiente

  /// BoxDecoration padrão para cards: fundo + borda 0.5px + border radius 16px.
  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
    color: color ?? backgroundSurface,
    borderRadius: BorderRadius.circular(radiusCard),
    border: Border.all(color: borderColor, width: 0.5),
  );

  /// Tema escuro principal. Usar no MaterialApp(theme: AppTheme.darkTheme).
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: backgroundSurface,
      ),
      scaffoldBackgroundColor: backgroundPrimary,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundPrimary,
        foregroundColor: textPrimary,
        elevation: 0,
        // 0.01em de letter-spacing nos títulos para legibilidade consistente
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.2, // 0.01 × 20sp
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          // pílula suave: radiusButton = 20px
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
        ),
      ),
      // Campos de texto: borda 0.5px em repouso, acento em foco, radius 14px
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderColor, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: borderColor, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textSecondary),
      ),
    );
  }
}
