// app_theme.dart - Design System do Sopro
// Centraliza todas as cores, tipografia e estilos do app.
// NUNCA use cores hardcodadas em widgets - use sempre AppTheme.

import 'package:flutter/material.dart';

/// Design system do Sopro.
/// Paleta: fundo azul escuro, acento vermelho vivo.
class AppTheme {
  AppTheme._();

  // Cores de fundo
  static const Color backgroundPrimary = Color(0xFF1A1A2E);
  static const Color backgroundSurface = Color(0xFF16213E);
  static const Color backgroundElevated = Color(0xFF0F3460);

  // Cores de acao
  static const Color accent = Color(0xFFE94560);   // CTA e urgencia
  static const Color success = Color(0xFF0F9B58);  // Gatilho resolvido
  static const Color warning = Color(0xFFF5A623);  // Gatilho pendente

  // Cores de texto
  static const Color textPrimary = Color(0xFFEAEAEA);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFF5A5A5A);

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
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}