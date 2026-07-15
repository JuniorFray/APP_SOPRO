// SearchStrategy — decide COMO pesquisar uma consulta já classificada.
//
// Segunda etapa da arquitetura:
//   Gemini → QueryNormalizer → SearchStrategy → AndroidGeocodingService →
//   CandidateFilter → LocationRanker → DecisionEngine
//
// Etapa A — além do provedor, emite SearchConstraints: os parâmetros EXATOS que o
// provedor deve aplicar na query (país, tipo de feature, viés) e o limite de
// distância usado depois pelo CandidateFilter. Determinístico, sem dependências.

import 'query_normalizer.dart';

// Provedor de busca escolhido para a consulta.
enum SearchProvider { photon, geocoder }

// Restrições de busca. Só os campos suportados pelo provedor são aplicados na
// query; os demais orientam o CandidateFilter (queryType, radiusKm, countryCode).
class SearchConstraints {
  // ISO 3166-1 alpha-2. Photon `countrycode` / Nominatim `countrycodes`.
  final String? countryCode;
  // Photon `layer` (valores oficiais: city, locality, district, state, ...).
  // Photon NÃO tem layer "poi" — POIs são filtrados por osmTags.
  final List<String> layers;
  // Photon `osm_tag` (key-only aceito): amenity, shop, tourism → restringe a POIs.
  final List<String> osmTags;
  // Limite de distância (km) aplicado pelo CandidateFilter. null = sem limite.
  final double? radiusKm;
  // Nominatim `bounded` (transforma viewbox em filtro). Photon usa `bbox` fixo.
  final bool bounded;
  // Aplica viés de proximidade (Photon lat/lon + location_bias_scale).
  final bool useBias;
  // Intenção original — usada pelo CandidateFilter para checar compatibilidade.
  final QueryKind queryType;

  const SearchConstraints({
    required this.queryType,
    this.countryCode,
    this.layers = const [],
    this.osmTags = const [],
    this.radiusKm,
    this.bounded = false,
    this.useBias = false,
  });

  // Representação compacta para log temporário.
  Map<String, dynamic> toLog() => {
        'countryCode': countryCode,
        'layers': layers,
        'osmTags': osmTags,
        'radiusKm': radiusKm,
        'bounded': bounded,
        'useBias': useBias,
        'queryType': queryType.name,
      };
}

// Plano de busca: provedor + restrições a aplicar.
class SearchPlan {
  final SearchProvider provider;
  final SearchConstraints constraints;
  const SearchPlan(this.provider, this.constraints);
}

class SearchStrategy {
  SearchStrategy._();

  // País-alvo do app (Brasil). Filtro em todos os provedores que suportam.
  static const _country = 'br';

  // Raio máximo (km) para estabelecimento sem cidade explícita — evita que um
  // POI homônimo distante (outro estado) entre no ranking. Configurável.
  static const _establishmentRadiusKm = 300.0;

  // Regra fixa por tipo. POIs via osm_tag (não há layer "poi" no Photon);
  // cidade/estado via layer; endereço/CEP via Geocoder nativo (com fallback).
  static SearchPlan plan(QueryKind kind) {
    switch (kind) {
      case QueryKind.establishment:
        return const SearchPlan(
          SearchProvider.photon,
          SearchConstraints(
            queryType: QueryKind.establishment,
            countryCode: _country,
            osmTags: ['amenity', 'shop', 'tourism'],
            radiusKm: _establishmentRadiusKm,
            useBias: true,
          ),
        );
      case QueryKind.city:
        return const SearchPlan(
          SearchProvider.photon,
          SearchConstraints(
            queryType: QueryKind.city,
            countryCode: _country,
            layers: ['city', 'locality'],
          ),
        );
      case QueryKind.state:
        return const SearchPlan(
          SearchProvider.photon,
          SearchConstraints(
            queryType: QueryKind.state,
            countryCode: _country,
            layers: ['state'],
          ),
        );
      case QueryKind.address:
      case QueryKind.zipcode:
        // Geocoder nativo (bounding box do usuário já é aplicada nativamente);
        // fallback Photon herda countryCode + viés.
        return SearchPlan(
          SearchProvider.geocoder,
          SearchConstraints(
            queryType: kind,
            countryCode: _country,
            useBias: true,
          ),
        );
    }
  }
}
