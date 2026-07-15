// LocationSourceResolver — classifica DE ONDE deve vir a localização de um
// ambiente criado por voz, ANTES de qualquer criação.
//
// Objetivo (Resolução Inteligente de Localização): "Criar ambiente Mercado"
// não deve mais usar o GPS cegamente. O assistente conversa até descobrir a
// localização correta. A classificação é deterministica e roda 100% no app
// (nenhuma dependência de Flutter/Riverpod/Gemini), o que a torna testável
// isoladamente — mesmo estilo de execution_plan.dart.
//
// A criação SÓ ocorre depois desta classificação (regra da sprint).

// Origem da localização de um ambiente. Espelha o enum location_source pedido.
enum LocationSource {
  // Localização atual do aparelho (GPS). Ex.: "Casa", "Oficina", "Trabalho".
  gpsCurrent,
  // Endereço ditado pelo usuário e geocodificado. Ex.: "Casa da mãe".
  addressText,
  // Busca de estabelecimento (geocoding forward). Ex.: "Assaí", "Mercado".
  placeSearch,
  // Ambiente já existente no banco — reutiliza, não cria (resolvido antes daqui).
  existingEnvironment,
  // Nome vazio / indeterminado — o chamador pede o nome antes de prosseguir.
  unknown,
}

class LocationSourceResolver {
  // Palavras que indicam o LOCAL ATUAL do usuário (usa GPS mediante confirmação).
  // Comparadas por igualdade exata (nome == palavra) para não capturar
  // "Mercado São Jorge" etc. — só o termo puro.
  static const _currentLocationWords = <String>{
    'casa', 'oficina', 'trabalho', 'servico', 'serviço', 'quarto',
    'escritorio', 'escritório', 'apartamento', 'ap', 'apê', 'ape',
  };

  // Categorias genéricas: exigem que o usuário diga QUAL antes de pesquisar.
  // NUNCA usam GPS. Ex.: "Mercado" → "Qual mercado?".
  static const _genericPlaceWords = <String>{
    'mercado', 'supermercado', 'farmacia', 'farmácia', 'hospital', 'academia',
    'escola', 'shopping', 'restaurante', 'correios', 'banco', 'loja', 'posto',
    'padaria', 'lanchonete', 'clinica', 'clínica',
  };

  // Preposições possessivas que sinalizam um endereço de terceiros/ referência
  // ("Casa da mãe", "Casa do João") — resolvido por endereço ditado.
  static final _possessiveRegex =
      RegExp(r'(^|\s)(da|do|de|das|dos)\s', caseSensitive: false);

  // Classifica a origem da localização a partir do NOME do ambiente.
  static LocationSource classify(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return LocationSource.unknown;
    final lower = trimmed.toLowerCase();

    // 1. Possessivo ("Casa da mãe") → endereço ditado (tem prioridade sobre
    //    palavra genérica: "Restaurante do Zé" vira endereço, não "qual?").
    if (_possessiveRegex.hasMatch(lower)) return LocationSource.addressText;

    // 2. Termo puro de local atual ("Casa", "Oficina") → GPS (com confirmação).
    if (_currentLocationWords.contains(lower)) return LocationSource.gpsCurrent;

    // 3. Categoria genérica pura ("Mercado", "Farmácia") → precisa de "qual?".
    if (_genericPlaceWords.contains(lower)) return LocationSource.placeSearch;

    // 4. Qualquer outro nome (marca/estabelecimento, "Assaí", "Mercado São
    //    Jorge") → busca direta.
    return LocationSource.placeSearch;
  }

  // True quando o nome é uma categoria genérica pura e precisa de especificação
  // ("Qual mercado?") antes de pesquisar.
  static bool needsSpecifier(String name) {
    final lower = name.trim().toLowerCase();
    if (_possessiveRegex.hasMatch(lower)) return false; // já é específico
    return _genericPlaceWords.contains(lower);
  }
}
