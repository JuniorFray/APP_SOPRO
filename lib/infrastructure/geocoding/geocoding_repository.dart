import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/database_provider.dart';
import '../providers/i_geocoding_provider.dart';
import 'android_geocoding_service.dart';
import 'geocoding_platform_interface.dart';

// Repositório de geocoding exposto via Riverpod.
//
// Usa AndroidGeocodingService diretamente (Android-first).
// Troca por IOSGeocodingService quando o suporte iOS for implementado (Fase 4).
class GeocodingRepository implements IGeocodingProvider {
  final GeocodingPlatformInterface _service;

  GeocodingRepository(this._service);

  // Busca forward com cascata cache → Geocoder → Photon
  @override
  Future<List<GeocodingResult>> search(String query) =>
      _service.search(query);

  // Geocoding reverso: coordenadas → nome do local
  @override
  Future<GeocodingResult?> reverse(double lat, double lon) =>
      _service.reverse(lat, lon);

  // Rótulo "Bairro, Cidade" das coordenadas (reverse via Photon, cacheado). Só a
  // cidade quando não há bairro; '' se indisponível. Usado pelo card de clima
  // para corrigir o nome que o OWM erra e trazer o bairro.
  Future<String> placeLabel(double lat, double lon) =>
      (_service as AndroidGeocodingService).userPlaceLabel(lat, lon);

  // Camada 3 — chamada pela UI quando usuário toca "Nenhum desses"
  // após ver resultados do Photon + LocationIQ.
  @override
  Future<List<GeocodingResult>> searchGoogle(String query,
      {double userLat = 0.0, double userLon = 0.0}) =>
      (_service as AndroidGeocodingService)
          .searchGooglePlaces(query,
              userLat: userLat, userLon: userLon);
}

// Provider do repositório — singleton no escopo do app
final geocodingRepositoryProvider = Provider<GeocodingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final service = AndroidGeocodingService(db.geocodingCacheDao);
  return GeocodingRepository(service);
});
