// EnvironmentTypeClassifier — decide, só pelo NOME do ambiente, se ele parece
// ser um mercado (e portanto deve ganhar uma lista de compras em vez de gatilhos).
//
// Determinístico e 100% no app — sem rede, sem Flutter, sem Gemini — mesmo estilo
// puro/testável do LocationSourceResolver e do QueryNormalizer.
//
// As listas abaixo (_genericMarketWords, _marketBrands) são propositalmente
// SIMPLES e FÁCEIS DE EDITAR: cresça-as conforme o feedback de uso real
// (novos apelidos genéricos e novas redes). A comparação de marca é por
// "contains" (não igualdade), para pegar "Assaí Osasco", "Carrefour Express" etc.
class EnvironmentTypeClassifier {
  EnvironmentTypeClassifier._();

  // Termos genéricos de mercado.
  static const _genericMarketWords = <String>{
    'mercado', 'supermercado', 'atacadao', 'atacadão', 'atacarejo',
    'hortifruti', 'sacolao', 'sacolão',
  };

  // Principais redes brasileiras (comparação por "contains" no nome normalizado).
  static const _marketBrands = <String>{
    'assai', 'assaí', 'carrefour', 'extra', 'pao de acucar', 'pão de açúcar',
    'walmart', 'dia', 'big', 'makro', 'condor', 'angeloni', 'comper',
    'super muffato', 'muffato', 'bistek', 'zaffari',
  };

  // Retorna true se o nome sugere um mercado (genérico OU marca conhecida).
  static bool suggestsMarket(String environmentName) {
    final lower = _normalize(environmentName);
    if (_genericMarketWords.any((w) {
      final nw = _normalize(w);
      return lower == nw || lower.contains(nw);
    })) {
      return true;
    }
    return _marketBrands.any((b) => lower.contains(_normalize(b)));
  }

  // Minúsculas, trim e remoção de acentos comuns do português (mesma abordagem
  // dos normalizadores já existentes no projeto), para casar "assaí"/"assai".
  static String _normalize(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éèê]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óòôõ]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ç', 'c');
}
