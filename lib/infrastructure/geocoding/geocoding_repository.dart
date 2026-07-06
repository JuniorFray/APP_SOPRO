import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/database_provider.dart';
import 'android_geocoding_service.dart';
import 'geocoding_platform_interface.dart';

// Repositório de geocoding exposto via Riverpod.
//
// Usa AndroidGeocodingService diretamente (Android-first).
// Troca por IOSGeocodingService quando o suporte iOS for implementado (Fase 4).
class GeocodingRepository {
  final GeocodingPlatformInterface _service;

  GeocodingRepository(this._service);

  // Busca forward com cascata cache → Geocoder → Photon
  Future<List<GeocodingResult>> search(String query) =>
      _service.search(query);

  // Geocoding reverso: coordenadas → nome do local
  Future<GeocodingResult?> reverse(double lat, double lon) =>
      _service.reverse(lat, lon);
}

// Provider do repositório — singleton no escopo do app
final geocodingRepositoryProvider = Provider<GeocodingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final service = AndroidGeocodingService(db.geocodingCacheDao);
  return GeocodingRepository(service);
});
