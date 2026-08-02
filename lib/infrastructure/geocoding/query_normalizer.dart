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
//   categoryOsmTag — osm_tag específico do Photon (ex.: "amenity:pharmacy") quando
//                   a consulta é de uma categoria/rede conhecida. FILTRA por TIPO
//                   de lugar em vez de por nome — resolve "farmácia"/"drogaria"/
//                   "droga raia" trazendo farmácias, não POIs homônimos.
//   isGenericCategory — categoria conhecida sem marca própria ("farmácia",
//                   "drogaria são paulo"): dispara viés/raio mais apertado e
//                   proximidade como critério PRIMÁRIO no ranking.
class NormalizedQuery {
  final String query;
  final QueryKind kind;
  final String? brandHint;
  final List<String> locationHints;
  final String? categoryHint;
  final String? categoryOsmTag;
  final bool isGenericCategory;
  const NormalizedQuery(
    this.query,
    this.kind, {
    this.brandHint,
    this.locationHints = const [],
    this.categoryHint,
    this.categoryOsmTag,
    this.isGenericCategory = false,
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

  static const _brandModifiers = {
    'atacadista', 'atacado', 'hipermercados',
    'distribuidora', 'comercio', 'comercial',
    'supermercados', 'farmácias', 'farmacias',
  };

  // Categoria genérica → osm_tag OFICIAL do Photon (filtra por TIPO de lugar, não
  // por nome). Chaves normalizadas (sem acento, minúsculas). Expansível.
  static const _categoryTags = {
    'farmacia':     'amenity:pharmacy',
    'drogaria':     'amenity:pharmacy',
    'mercado':      'shop:supermarket',
    'supermercado': 'shop:supermarket',
    'hipermercado': 'shop:supermarket',
    'padaria':      'shop:bakery',
    'acougue':      'shop:butcher',
    'hospital':     'amenity:hospital',
    'clinica':      'amenity:clinic',
    'posto':        'amenity:fuel',
    'restaurante':  'amenity:restaurant',
    'lanchonete':   'amenity:fast_food',
    'banco':        'amenity:bank',
    'academia':     'leisure:fitness_centre',
    'shopping':     'shop:mall',
    'loja':         'shop',
  };

  // Redes/marcas conhecidas que NÃO contêm a palavra da categoria mas SÃO daquela
  // categoria (ex.: "Droga Raia" é farmácia). Garante classificação como
  // establishment + osm_tag correto. Chaves normalizadas. Expansível.
  static const _brandTags = {
    'droga raia': 'amenity:pharmacy',
    'drogaraia':  'amenity:pharmacy',
    'drogasil':   'amenity:pharmacy',
    'drogao':     'amenity:pharmacy',
    'ultrafarma': 'amenity:pharmacy',
    'pague menos':'amenity:pharmacy',
    'panvel':     'amenity:pharmacy',
    'nissei':     'amenity:pharmacy',
    'farmais':    'amenity:pharmacy',
    'atacadao':   'shop:supermarket',
    'carrefour':  'shop:supermarket',
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

    // 3. Sufixos = modificadores de local candidatos.
    //    COM categoria líder ("farmácia são paulo"): o núcleo inteiro é contexto
    //    (categoria + LUGAR), então geramos sufixos do CORE COMPLETO (mais longo
    //    primeiro) — assim "são paulo" resolve como UNIDADE no Stage 1, sem
    //    quebrar em "paulo". SEM categoria (marca real, "Assaí Gonzaga"): o 1º
    //    token é a marca (discriminador) e só o restante é modificador de local.
    final hintSource = categoryHint != null
        ? core
        : (core.length > 1 ? core.sublist(1) : const <String>[]);
    // Rede conhecida SEM tokens extras ("droga raia") é marca pura — seus tokens
    // ("raia") NÃO são local; não gera hint pra não recentrar o viés errado.
    final pureBrand = _brandTags.containsKey(_strip(query.toLowerCase().trim()));
    final locationHints = <String>[];
    if (!pureBrand) {
      for (var i = 0; i < hintSource.length; i++) {
        final suffix = hintSource.sublist(i).join(' ');
        // Exclui sufixos compostos apenas de modificadores de categoria/marca.
        // Ex.: "atacadista" sozinho não é local geográfico.
        // "atacadista piracicaba" → "piracicaba" não é modificador → incluído.
        final suffixTokens = suffix
            .split(RegExp(r'\s+'))
            .map((t) => _strip(t.toLowerCase()))
            .toList();
        final allModifiers = suffixTokens.every(
            (t) => _categoryWords.contains(t) || _brandModifiers.contains(t));
        if (!allModifiers) locationHints.add(suffix);
      }
    }

    final osmTag = _resolveOsmTag(_strip(query.toLowerCase()), categoryHint);
    // Genérica = categoria conhecida líder (só categoria, ou categoria + lugar).
    // Uma marca própria ("Assaí", "Droga Raia") NÃO é genérica.
    final generic = categoryHint != null;

    return NormalizedQuery(
      query,
      kind,
      brandHint: brandHint,
      locationHints: locationHints,
      categoryHint: categoryHint,
      categoryOsmTag: osmTag,
      isGenericCategory: generic,
    );
  }

  // Resolve o osm_tag: categoria líder → marca conhecida (qualquer posição) →
  // categoria em qualquer posição. [qStrip] já vem sem acento e minúsculo.
  static String? _resolveOsmTag(String qStrip, String? categoryHead) {
    if (categoryHead != null) {
      final tag = _categoryTags[_strip(categoryHead.toLowerCase())];
      if (tag != null) return tag;
    }
    for (final e in _brandTags.entries) {
      if (qStrip.contains(e.key)) return e.value;
    }
    for (final e in _categoryTags.entries) {
      if (qStrip.contains(e.key)) return e.value;
    }
    return null;
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
    // Rede conhecida sem a palavra da categoria ("Droga Raia") também é POI.
    final qs = _strip(q);
    if (_brandTags.keys.any((w) => qs.contains(w))) {
      return QueryKind.establishment;
    }
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
