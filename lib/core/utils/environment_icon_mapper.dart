// Mapeia nomes de ambientes para ícones Lucide monocromáticos (estilo linha).
// Busca por palavras-chave case-insensitive, sem acentos.
// Usado nos cards da Home, na aba Ambientes e na tela de detalhe do ambiente.
//
// Design flat premium: o ícone é monocromático (tinta única AppColors.iconTileTint)
// e o container de fundo é IGUAL para todos os ambientes (branco ~6%), sem cor por
// tipo. Aqui devolvemos só o IconData — a cor/fundo vive no widget consumidor.

import 'package:flutter/widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

class EnvironmentIconMapper {
  EnvironmentIconMapper._();

  // Retorna o ícone Lucide correspondente ao nome do ambiente.
  // Fallback: mapPin para nomes não reconhecidos.
  static IconData iconFor(String name) {
    final n = _normalize(name);

    if (_hits(n, ['casa', 'apartamento', 'lar', 'home', 'residencia'])) {
      return LucideIcons.home;
    } else if (_hits(n, ['trabalho', 'escritorio', 'empresa', 'office', 'work', 'sede'])) {
      return LucideIcons.briefcase;
    } else if (_hits(n, ['mercado', 'supermercado', 'feira', 'market', 'hortifruti'])) {
      return LucideIcons.shoppingCart;
    } else if (_hits(n, ['farmacia', 'drogaria', 'remedio', 'pharmacy'])) {
      return LucideIcons.cross;
    } else if (_hits(n, ['medico', 'clinica', 'hospital', 'ubs', 'saude', 'laboratorio'])) {
      return LucideIcons.stethoscope;
    } else if (_hits(n, ['academia', 'gym', 'crossfit', 'fitness', 'esporte', 'treino'])) {
      return LucideIcons.dumbbell;
    } else if (_hits(n, ['escola', 'faculdade', 'colegio', 'curso', 'universidade', 'ead'])) {
      return LucideIcons.graduationCap;
    } else if (_hits(n, ['banco', 'caixa', 'cartorio', 'loteria'])) {
      return LucideIcons.landmark;
    } else if (_hits(n, ['posto', 'gasolina', 'oficina', 'mecanico', 'borracharia'])) {
      return LucideIcons.fuel;
    } else if (_hits(n, ['restaurante', 'lanchonete', 'pizzaria', 'churrascaria'])) {
      return LucideIcons.utensils;
    } else if (_hits(n, ['padaria', 'cafe', 'bakery', 'cafeteria', 'confeitaria'])) {
      return LucideIcons.coffee;
    } else if (_hits(n, ['parque', 'praca', 'jardim', 'park', 'reserva'])) {
      return LucideIcons.trees;
    } else if (_hits(n, ['loja', 'shopping', 'mall', 'centro', 'galeria'])) {
      return LucideIcons.shoppingBag;
    } else {
      return LucideIcons.mapPin;
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
