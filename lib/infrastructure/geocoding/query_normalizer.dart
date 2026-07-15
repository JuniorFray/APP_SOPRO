// QueryNormalizer — classifica UMA consulta de geocoding, sem pesquisar nada.
//
// Primeira etapa da nova arquitetura de resolução de localização:
//   Gemini → QueryNormalizer → SearchStrategy → AndroidGeocodingService →
//   LocationRanker → DecisionEngine
//
// É determinístico e roda 100% no app (nenhuma dependência de rede / Flutter /
// Gemini), o que o torna testável isoladamente — mesmo estilo do
// LocationSourceResolver e do execution_plan.dart.
//
// Responsabilidade ÚNICA: dado o texto bruto, devolver a ESTRUTURA da consulta
// {query, kind, brand/location/category}. Não decide COMO pesquisar (SearchStrategy)
// nem pesquisa. Etapa 1.6 — SEM conhecimento geográfico: não conhece cidades nem
// bairros; apenas separa o núcleo (marca) dos modificadores (locationHints). Quem
// interpreta os modificadores contra dados reais é o LocationRanker.

// Tipo da consulta. Decide, na SearchStrategy, o provedor e o viés.
enum QueryKind { city, state, zipcode, address, establishment }

// Consulta já classificada. [query] é o texto (trim aplicado); [kind] o tipo.
// Hints extraídos deterministicamente (só p/ establishment; null/[] caso contrário):
//   brandHint     — núcleo do nome, após remover a categoria líder ("Litoral Plaza
//                   Praia Grande", "Assaí Gonzaga", "Ana Costa"). A "cabeça" (1º
//                   token) é o discriminador de marca usado pelo Ranker.
//   locationHints — sufixos do núcleo após a marca: possíveis modificadores de
//                   local ("Praia Grande", "Gonzaga"). SEM saber que são lugares —
//                   o Ranker confirma casando contra city/district/state/etc.
//   categoryHint  — tipo genérico quando lidera o texto ("Shopping", "Hospital").
class NormalizedQuery {
  final String query;
  final QueryKind kind;
  final String? brandHint;
  final List<String> locationHints;
  final String? categoryHint;
  const NormalizedQuery(
    this.query,
    this.kind, {
    this.brandHint,
    this.locationHints = const [],
    this.categoryHint,
  });
}

class QueryNormalizer {
  QueryNormalizer._();

  // Palavras de logradouro → classificam a consulta como endereço (Geocoder).
  static const _streetWords = [
    'rua', 'av.', 'avenida', 'travessa', 'alameda', 'estrada',
    'rodovia', 'praca', 'praça', 'largo',
  ];

  // Categorias/marcas de estabelecimento → Photon COM viés de proximidade.
  static const _establishmentWords = [
    'shopping', 'plaza', 'mercado', 'supermercado', 'hipermercado',
    'atacad', 'atacadista', 'farmacia', 'farmácia', 'drogaria',
    'hospital', 'clinica', 'clínica', 'posto', 'restaurante',
    'lanchonete', 'padaria', 'academia', 'banco', 'loja',
    'mcdonald', 'burger', 'assai', 'assaí', 'carrefour',
    'santa casa', 'pao de acucar', 'pão de açúcar',
  ];

  // Nomes de UF por extenso → busca GLOBAL (sem viés). Match exato (== q).
  static const _stateNames = {
    'acre', 'alagoas', 'amapa', 'amapá', 'amazonas', 'bahia', 'ceara', 'ceará',
    'distrito federal', 'espirito santo', 'espírito santo', 'goias', 'goiás',
    'maranhao', 'maranhão', 'mato grosso', 'mato grosso do sul', 'minas gerais',
    'para', 'pará', 'paraiba', 'paraíba', 'parana', 'paraná', 'pernambuco',
    'piaui', 'piauí', 'rio de janeiro', 'rio grande do norte',
    'rio grande do sul', 'rondonia', 'rondônia', 'roraima', 'santa catarina',
    'sao paulo', 'são paulo', 'sergipe', 'tocantins',
  };

  // Tipos genéricos que, liderando o texto, viram categoryHint. NÃO é
  // conhecimento geográfico — é o tipo semântico do estabelecimento.
  static const _categoryWords = {
    'shopping', 'mercado', 'supermercado', 'hipermercado', 'farmacia',
    'drogaria', 'hospital', 'clinica', 'posto', 'restaurante', 'lanchonete',
    'padaria', 'academia', 'banco', 'loja',
  };

  // Classifica a consulta (determinístico, sem rede). Ordem importa:
  // CEP → estabelecimento (categoria/marca) → endereço (logradouro/número) →
  // estado (UF por extenso) → cidade (padrão). Extrai hints só p/ establishment.
  static NormalizedQuery normalize(String raw) {
    final query = raw.trim();
    final q = query.toLowerCase();
    final kind = _classify(q);
    if (kind != QueryKind.establishment) return NormalizedQuery(query, kind);
    return _withHints(query, kind);
  }

  // Extrai a ESTRUTURA de uma consulta de estabelecimento — sem geografia:
  //   1. Se um tipo genérico lidera o texto → categoryHint e é removido do núcleo.
  //   2. O restante é o núcleo (candidato a marca) → brandHint.
  //   3. Os tokens após a cabeça do núcleo são possíveis modificadores de local →
  //      locationHints (sufixos progressivos). Sem afirmar que são lugares; o
  //      LocationRanker confirma casando contra os campos dos candidatos reais.
  static NormalizedQuery _withHints(String query, QueryKind kind) {
    final tokens =
        query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // 1. Categoria líder.
    String? categoryHint;
    var start = 0;
    if (tokens.isNotEmpty &&
        _categoryWords.contains(_strip(tokens.first.toLowerCase()))) {
      categoryHint = tokens.first;
      start = 1;
    }

    // 2. Núcleo (após a categoria) = marca.
    final core = tokens.sublist(start);
    final brandHint = core.isEmpty ? null : core.join(' ');

    // 3. Sufixos após a cabeça do núcleo = modificadores de local candidatos.
    final tail = core.length > 1 ? core.sublist(1) : const <String>[];
    final locationHints = <String>[
      for (var i = 0; i < tail.length; i++) tail.sublist(i).join(' '),
    ];

    return NormalizedQuery(
      query,
      kind,
      brandHint: brandHint,
      locationHints: locationHints,
      categoryHint: categoryHint,
    );
  }

  // Remove acentos (usado só p/ comparar categoria sem depender de acentuação).
  static String _strip(String s) => s
      .replaceAll(RegExp(r'[áàãâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòõôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');

  static QueryKind _classify(String q) {
    if (RegExp(r'^\d{5}-?\d{3}$').hasMatch(q)) return QueryKind.zipcode;
    if (_establishmentWords.any((w) => q.contains(w))) {
      return QueryKind.establishment;
    }
    final hasStreetWord = _streetWords.any((w) => q.contains(w));
    final hasNumber = RegExp(r'\d').hasMatch(q);
    if (hasStreetWord || hasNumber) return QueryKind.address;
    if (_stateNames.contains(q)) return QueryKind.state;
    return QueryKind.city;
  }
}
