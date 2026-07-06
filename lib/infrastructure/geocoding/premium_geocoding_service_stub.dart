import 'geocoding_platform_interface.dart';

// Slot reservado para provedor premium (HERE, Google Places, etc).
//
// Ativar via feature flag quando a escala do produto exigir.
// Não implementado — zero custo até ser necessário.
//
// Candidatos:
//   HERE  → https://geocode.search.hereapi.com/v1/geocode
//   Google Places → https://places.googleapis.com/v1/places:autocomplete
class PremiumGeocodingService implements GeocodingPlatformInterface {
  final String apiKey;

  PremiumGeocodingService({required this.apiKey});

  @override
  Future<List<GeocodingResult>> search(String query) async {
    // TODO: implementar HERE ou Google Places quando escala exigir
    throw UnimplementedError('Provedor premium não configurado');
  }

  @override
  Future<GeocodingResult?> reverse(double lat, double lon) async {
    // TODO: implementar reverse geocoding premium quando escala exigir
    throw UnimplementedError('Provedor premium não configurado');
  }
}
