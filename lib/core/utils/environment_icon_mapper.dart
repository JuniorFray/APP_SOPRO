// Mapeia nomes de ambientes para emoji + cor de fundo ilustrativa.
// Busca por palavras-chave case-insensitive, sem acentos.
// Usado nos cards da HomeScreen e na tela de detalhe do ambiente.

import 'package:flutter/material.dart';

// Resultado do mapeamento: emoji e cor de fundo do container de ícone
typedef EnvironmentVisual = ({String emoji, Color color});

class EnvironmentIconMapper {
  EnvironmentIconMapper._();

  // Retorna emoji e cor de fundo correspondentes ao nome do ambiente.
  // Fallback: 📍 cinza para nomes não reconhecidos.
  static EnvironmentVisual getVisual(String name) {
    final n = _normalize(name);

    if (_hits(n, ['casa', 'apartamento', 'lar', 'home', 'residencia'])) {
      return (emoji: '🏠', color: const Color(0x26E8445A));
    } else if (_hits(n, ['trabalho', 'escritorio', 'empresa', 'office', 'work', 'sede'])) {
      return (emoji: '🏢', color: const Color(0x26639922));
    } else if (_hits(n, ['mercado', 'supermercado', 'feira', 'market', 'hortifruti'])) {
      return (emoji: '🛒', color: const Color(0x26378ADD));
    } else if (_hits(n, ['farmacia', 'drogaria', 'remedio', 'pharmacy'])) {
      return (emoji: '💊', color: const Color(0x260F9B58));
    } else if (_hits(n, ['medico', 'clinica', 'hospital', 'ubs', 'saude', 'laboratorio'])) {
      return (emoji: '🏥', color: const Color(0x26378ADD));
    } else if (_hits(n, ['academia', 'gym', 'crossfit', 'fitness', 'esporte', 'treino'])) {
      return (emoji: '🏋', color: const Color(0x26639922));
    } else if (_hits(n, ['escola', 'faculdade', 'colegio', 'curso', 'universidade', 'ead'])) {
      return (emoji: '🎓', color: const Color(0x26534AB7));
    } else if (_hits(n, ['banco', 'caixa', 'cartorio', 'loteria'])) {
      return (emoji: '🏦', color: const Color(0x26534AB7));
    } else if (_hits(n, ['posto', 'gasolina', 'oficina', 'mecanico', 'borracharia'])) {
      return (emoji: '⛽', color: const Color(0x26F5A623));
    } else if (_hits(n, ['obra', 'construcao', 'reforma', 'canteiro'])) {
      return (emoji: '🏗', color: const Color(0x26F5A623));
    } else if (_hits(n, ['restaurante', 'lanchonete', 'pizzaria', 'churrascaria'])) {
      return (emoji: '🍽', color: const Color(0x26E8445A));
    } else if (_hits(n, ['padaria', 'cafe', 'bakery', 'cafeteria', 'confeitaria'])) {
      return (emoji: '☕', color: const Color(0x26F5A623));
    } else if (_hits(n, ['parque', 'praca', 'jardim', 'park', 'reserva'])) {
      return (emoji: '🌳', color: const Color(0x260F9B58));
    } else if (_hits(n, ['loja', 'shopping', 'mall', 'centro', 'galeria'])) {
      return (emoji: '🛍', color: const Color(0x26534AB7));
    } else {
      return (emoji: '📍', color: const Color(0x268A8A9A));
    }
  }

  // Retorna true se o nome normalizado contém pelo menos uma das palavras-chave
  static bool _hits(String normalized, List<String> keywords) =>
      keywords.any(normalized.contains);

  // Converte para minúsculas e remove acentos comuns do português
  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll(RegExp('[úü]'), 'u')
      .replaceAll('ç', 'c');
}
