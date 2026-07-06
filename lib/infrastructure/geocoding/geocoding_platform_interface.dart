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

  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.source,
    this.hasNumber = false,
  });

  @override
  String toString() =>
      'GeocodingResult(displayName: $displayName, lat: $lat, lon: $lon, source: $source)';
}
