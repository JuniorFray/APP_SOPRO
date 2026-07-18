// Contrato de geocoding — permite trocar implementação por plataforma sem
// alterar os chamadores.
//
// Android: AndroidGeocodingService (Geocoder nativo + Photon fallback).
// iOS futuro: IOSGeocodingService via MKLocalSearch + CLGeocoder.
// Premium futuro: PremiumGeocodingService (HERE / Google Places).
abstract class GeocodingPlatformInterface {
  // Busca forward: nome de local ou endereço → lista de resultados ordenada por confiança.
  // Retorna lista vazia se nenhum resultado for encontrado.
  Future<List<GeocodingResult>> search(String query);

  // Geocoding reverso: coordenadas → nome do local mais próximo.
  // Retorna null se nenhum resultado for encontrado.
  Future<GeocodingResult?> reverse(double lat, double lon);
}

// Resultado de geocoding normalizado — independente da fonte.
class GeocodingResult {
  // Nome exibível do local (ex: "Av. Paulista, 1578 — São Paulo, SP")
  final String displayName;

  final double lat;
  final double lon;

  // Fonte que gerou o resultado: 'geocoder_native', 'photon' ou 'premium'
  final String source;

  // Indica que o resultado inclui número de rua (precisão de endereço completo)
  final bool hasNumber;

  // ── Campos enriquecidos (Etapa 1 — insumo do LocationRanker) ──────────────
  // Preenchidos quando a fonte os fornece; vazios/null caso contrário. Nenhum
  // consumidor depende deles ainda (foundation) — o displayName segue autoritativo.
  final String name;        // Nome do estabelecimento/local ("Assaí Atacadista")
  final String address;     // Logradouro + número ("Av. Kennedy, 1234")
  // Bairro / distrito / suburb (Photon `properties.district` = "city district or
  // suburb"). Discriminador de local mais fino que a cidade — é ele que casa o
  // locationHint do QueryNormalizer ("Gonzaga"). Vazio quando a fonte não informa.
  final String district;
  final String city;        // Município
  final String state;       // UF / estado
  final String country;     // País
  final String postalCode;  // CEP
  // Tipo estrutural da feature (Photon `properties.type`): house, street,
  // locality, district, city, county, state, country, other. Vazio quando a
  // fonte não informa (Geocoder nativo). Usado pelo CandidateFilter.
  final String featureType;
  // Distância em metros até o usuário. null = usuário desconhecido / sem viés.
  // Calculada pelo LocationRanker via copyWith (não pela fonte).
  final double? distanceToUser;

  // ID externo do provider (Google place_id).
  // Vazio para Photon e LocationIQ.
  final String placeId;

  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.source,
    this.hasNumber = false,
    this.name = '',
    this.address = '',
    this.district = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.postalCode = '',
    this.featureType = '',
    this.distanceToUser,
    this.placeId = '',
  });

  // Cópia com distância preenchida pelo Ranker (único campo que ele altera).
  GeocodingResult copyWith({double? distanceToUser}) => GeocodingResult(
        displayName: displayName,
        lat: lat,
        lon: lon,
        source: source,
        hasNumber: hasNumber,
        name: name,
        address: address,
        district: district,
        city: city,
        state: state,
        country: country,
        postalCode: postalCode,
        featureType: featureType,
        distanceToUser: distanceToUser ?? this.distanceToUser,
        placeId: placeId,
      );

  @override
  String toString() =>
      'GeocodingResult(displayName: $displayName, lat: $lat, lon: $lon, source: $source)';
}
