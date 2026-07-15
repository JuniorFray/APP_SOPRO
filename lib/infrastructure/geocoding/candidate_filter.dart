// CandidateFilter — elimina candidatos claramente inválidos ENTRE o Provider e o
// LocationRanker.
//
//   Provider → CandidateFilter → LocationRanker
//
// Objetivo (Etapa B): o Ranker deixa de "consertar" lixo — o lixo nem chega. As
// regras são determinísticas, sem rede/Flutter, testáveis isoladamente.
//
// Descarta candidatos que sejam: sem coordenadas, de outro país, distantes além
// do limite, de tipo incompatível com a intenção, ou de baixa qualidade.

import 'dart:math' as math;

import 'geocoding_platform_interface.dart';
import 'query_normalizer.dart';

// Candidato removido + motivo (para log/auditoria).
class RemovedCandidate {
  final GeocodingResult candidate;
  final String reason;
  const RemovedCandidate(this.candidate, this.reason);
}

// Saída do filtro: mantidos + removidos (com motivo).
class FilteredCandidates {
  final List<GeocodingResult> kept;
  final List<RemovedCandidate> removed;
  const FilteredCandidates(this.kept, this.removed);
}

class CandidateFilter {
  CandidateFilter._();

  // Tipos de feature (Photon) que representam LUGARES administrativos, não POIs.
  static const _placeTypes = {
    'city', 'county', 'state', 'country', 'locality', 'district'
  };
  // Tipos de feature que representam endereço/POI, não lugar administrativo.
  static const _addressTypes = {'house', 'street', 'other'};

  // Nomes aceitos para o país-alvo (Photon devolve por extenso, pt ou en).
  static const _countryNames = {'br': {'brasil', 'brazil'}};

  static FilteredCandidates filter(
    List<GeocodingResult> input, {
    required QueryKind queryType,
    String? countryCode,
    double? radiusKm,
    double? userLat,
    double? userLon,
  }) {
    final kept = <GeocodingResult>[];
    final removed = <RemovedCandidate>[];
    final hasUser =
        userLat != null && userLon != null && userLat != 0.0 && userLon != 0.0;

    for (final c in input) {
      final reason = _reject(
        c,
        queryType: queryType,
        countryCode: countryCode,
        radiusKm: radiusKm,
        userLat: hasUser ? userLat : null,
        userLon: hasUser ? userLon : null,
      );
      if (reason == null) {
        kept.add(c);
      } else {
        removed.add(RemovedCandidate(c, reason));
      }
    }
    return FilteredCandidates(kept, removed);
  }

  // Retorna o motivo de rejeição, ou null se o candidato é válido. Ordem: coords
  // → país → distância → tipo×intenção → qualidade. Campos ausentes (ex.: tipo/
  // país vazios do Geocoder nativo) NÃO derrubam o candidato (só filtra o que sabe).
  static String? _reject(
    GeocodingResult c, {
    required QueryKind queryType,
    String? countryCode,
    double? radiusKm,
    double? userLat,
    double? userLon,
  }) {
    // 1. Sem coordenadas.
    if (c.lat == 0.0 && c.lon == 0.0) return 'no_coordinates';

    // 2. Outro país (só quando o candidato informa o país).
    if (countryCode != null && c.country.isNotEmpty) {
      final accepted = _countryNames[countryCode] ?? const {};
      if (accepted.isNotEmpty && !accepted.contains(_norm(c.country))) {
        return 'other_country';
      }
    }

    // 3. Distância acima do limite (quando aplicável e há usuário).
    if (radiusKm != null && userLat != null && userLon != null) {
      final meters = _haversine(userLat, userLon, c.lat, c.lon);
      if (meters > radiusKm * 1000) return 'too_far';
    }

    // 4. Tipo incompatível com a intenção (só quando o tipo é conhecido).
    final t = c.featureType.toLowerCase();
    if (t.isNotEmpty) {
      switch (queryType) {
        case QueryKind.establishment:
          // POI não pode ser cidade/estado/bairro administrativo.
          if (_placeTypes.contains(t)) return 'type_mismatch_place';
        case QueryKind.city:
        case QueryKind.state:
          // Cidade/estado não pode ser endereço/POI.
          if (_addressTypes.contains(t)) return 'type_mismatch_address';
          if (queryType == QueryKind.state && t != 'state' && t != 'country') {
            return 'type_mismatch_state';
          }
        case QueryKind.address:
        case QueryKind.zipcode:
          // Endereço não pode ser cidade/estado/bairro administrativo.
          if (_placeTypes.contains(t)) return 'type_mismatch_place';
      }
    }

    // 5. Baixa qualidade estrutural.
    if (c.displayName.trim().isEmpty) return 'low_quality';

    return null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[áàãâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòõôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
