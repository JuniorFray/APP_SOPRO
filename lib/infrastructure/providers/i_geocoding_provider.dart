import '../geocoding/geocoding_platform_interface.dart';

// IGeocodingProvider — contrato comum de geocoding (Tool Provider, spec
// voice_structure_doc/architecture/08-Tool-Providers.md).
//
// Abstrai forward/reverse/place-search para que Skills e Planner não dependam
// da implementação concreta (Android nativo, Photon, Google Places, iOS futuro).
// Camada fina: o GeocodingRepository atual já satisfaz este contrato — só
// declara `implements`, sem reescrever lógica.
abstract class IGeocodingProvider {
  // Busca forward: texto → lista de locais candidatos.
  Future<List<GeocodingResult>> search(String query);

  // Geocoding reverso: coordenadas → nome do local.
  Future<GeocodingResult?> reverse(double lat, double lon);

  // Camada premium (Google Places) — fallback quando o usuário rejeita os
  // resultados gratuitos. Mantido no contrato por ser ponto de troca de provedor.
  Future<List<GeocodingResult>> searchGoogle(String query,
      {double userLat = 0.0, double userLon = 0.0});
}
