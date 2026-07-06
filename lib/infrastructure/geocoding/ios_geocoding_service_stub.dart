import 'geocoding_platform_interface.dart';

// Stub iOS — implementação real pendente para a Fase 4.
//
// Mapeamento futuro:
//   search()  → MKLocalSearchRequest + MKLocalSearch.start() via MethodChannel Swift
//   reverse() → CLGeocoder.reverseGeocodeLocation() via MethodChannel Swift
class IOSGeocodingService implements GeocodingPlatformInterface {
  @override
  Future<List<GeocodingResult>> search(String query) async {
    // TODO iOS: usar MKLocalSearch via MethodChannel Swift
    throw UnsupportedError('Geocoding iOS não implementado ainda');
  }

  @override
  Future<GeocodingResult?> reverse(double lat, double lon) async {
    // TODO iOS: usar CLGeocoder.reverseGeocodeLocation() via MethodChannel Swift
    throw UnsupportedError('Reverse geocoding iOS não implementado ainda');
  }
}
