// LocationRanker — ordena candidatos de geocoding e classifica a CONFIANÇA da
// resolução. Sem IA, sem Gemini, sem pesos numéricos: tudo determinístico.
//
// Quarta etapa da arquitetura:
//   Gemini → QueryNormalizer → SearchStrategy → AndroidGeocodingService →
//   LocationRanker → DecisionEngine
//
// Ordenação (prioridade fixa, tier menor = mais forte):
//   0. Nome exatamente igual à consulta
//   1. Marca bate E um locationHint bate       (marca + local)
//   2. Marca bate                              (só marca)
//   3. Um locationHint bate                    (só local)
//   4. Nome começa igual à consulta
//   5. Nome contém a consulta
//   6. Sem casamento
//   Desempates: mesmo município do usuário → menor distância ao usuário.
//
// locationHints vêm do QueryNormalizer SEM saber que são lugares. Aqui eles são
// confirmados casando contra os campos REAIS do candidato (city/district/state/
// displayName/address) — é o Ranker que "interpreta" a geografia, sem listas fixas.
//
// Etapa 2 — o rank() devolve um RankResult com confiança (high/medium/low) e um
// motivo textual, consumidos pelo DecisionEngine (HomeScreen).

import 'dart:math' as math;

import 'geocoding_platform_interface.dart';

// Confiança da resolução — dirige a decisão (criar / confirmar / listar).
enum LocationConfidence { high, medium, low }

// Saída do Ranker: candidatos ordenados + confiança + motivo determinístico.
// reason ∈ { exact_match, brand_match, city_match, duplicate_locations,
//            generic_query, ambiguous, no_match, single_candidate }.
class RankResult {
  final List<GeocodingResult> orderedCandidates;
  final LocationConfidence confidence;
  final String reason;
  const RankResult(this.orderedCandidates, this.confidence, this.reason);
}

class LocationRanker {
  LocationRanker._();

  // Distância (m) abaixo da qual dois candidatos de mesmo nome são o MESMO local.
  static const _duplicateMeters = 500.0;

  // Ordena e classifica a confiança. [userCity] alimenta o desempate por
  // município do usuário. [brandHint]/[locationHints] vêm do QueryNormalizer.
  static RankResult rank(
    String query,
    List<GeocodingResult> results, {
    double? userLat,
    double? userLon,
    String userCity = '',
    String? brandHint,
    List<String> locationHints = const [],
    String? categoryHint,
  }) {
    if (results.isEmpty) {
      return const RankResult([], LocationConfidence.low, 'no_match');
    }

    final q = _norm(query);
    final userCityN = _norm(userCity);
    final brandHead = _headToken(brandHint);
    final hints = locationHints.map(_norm).where((h) => h.isNotEmpty).toList();
    final hasUser =
        userLat != null && userLon != null && userLat != 0.0 && userLon != 0.0;

    // Preenche a distância ao usuário (desempate) antes de ordenar.
    final list = results
        .map((r) => hasUser
            ? r.copyWith(distanceToUser: _haversine(userLat, userLon, r.lat, r.lon))
            : r)
        .toList();

    list.sort((a, b) {
      final ta = _tier(a, q, brandHead, hints);
      final tb = _tier(b, q, brandHead, hints);
      if (ta != tb) return ta.compareTo(tb);
      if (userCityN.isNotEmpty) {
        final ma = _norm(a.city) == userCityN ? 0 : 1;
        final mb = _norm(b.city) == userCityN ? 0 : 1;
        if (ma != mb) return ma.compareTo(mb);
      }
      final da = a.distanceToUser ?? double.infinity;
      final db = b.distanceToUser ?? double.infinity;
      return da.compareTo(db);
    });

    return _classify(list, query, q, brandHead, hints, brandHint, categoryHint);
  }

  // ── Confiança (determinística) ────────────────────────────────────────────
  static RankResult _classify(
    List<GeocodingResult> ordered,
    String query,
    String q,
    String brandHead,
    List<String> hints,
    String? brandHint,
    String? categoryHint,
  ) {
    final first = ordered.first;
    final exactFirst = nameEquals(first, query);
    final brandFirst = _brandMatches(first, brandHead);
    final locFirst = _locationMatches(first, hints);

    // 1 candidato → resolve.
    if (ordered.length == 1) {
      final reason = exactFirst
          ? 'exact_match'
          : brandFirst
              ? 'brand_match'
              : locFirst
                  ? 'city_match'
                  : 'single_candidate';
      return RankResult(ordered, LocationConfidence.high, reason);
    }

    final second = ordered[1];

    // Mesmo local duplicado em bases distintas (mesmo nome, < 500 m).
    if (sameName(first, second) &&
        distanceBetween(first, second) < _duplicateMeters) {
      return RankResult(ordered, LocationConfidence.high, 'duplicate_locations');
    }

    // Consulta genérica pura (só categoria, sem marca) → ambígua, lista.
    if (_isGeneric(brandHint, categoryHint)) {
      return RankResult(ordered, LocationConfidence.low, 'generic_query');
    }

    // Primeiro claramente superior ao segundo → resolve.
    if (isClearlyBetter(first, second, query, brandHead, hints)) {
      final reason = exactFirst
          ? 'exact_match'
          : (q.isNotEmpty && _name(first).contains(q))
              ? 'brand_match'
              : locFirst
                  ? 'city_match'
                  : 'brand_match';
      return RankResult(ordered, LocationConfidence.high, reason);
    }

    // Primeiro é o provável, mas há concorrência → confirma apenas o primeiro.
    if (brandFirst || locFirst) {
      return RankResult(
          ordered, LocationConfidence.medium, brandFirst ? 'brand_match' : 'city_match');
    }

    // Nada distingue → lista.
    return RankResult(ordered, LocationConfidence.low, 'ambiguous');
  }

  // O primeiro vence o segundo por um critério determinístico e exclusivo?
  static bool isClearlyBetter(
    GeocodingResult first,
    GeocodingResult second,
    String query,
    String brandHead,
    List<String> hints,
  ) {
    final q = _norm(query);
    final n1 = _name(first);
    final n2 = _name(second);
    // 1. Primeiro é match exato do nome; o segundo não.
    if (nameEquals(first, query) && !nameEquals(second, query)) return true;
    // 2. Primeiro contém o nome COMPLETO da consulta; o segundo não.
    if (q.isNotEmpty && n1.contains(q) && !n2.contains(q)) return true;
    // 3. Primeiro casa a marca (cabeça); o segundo é outra marca.
    if (brandHead.isNotEmpty && n1.contains(brandHead) && !n2.contains(brandHead)) {
      return true;
    }
    // 4. Primeiro casa um locationHint; o segundo não.
    if (_locationMatches(first, hints) && !_locationMatches(second, hints)) {
      return true;
    }
    return false;
  }

  // Tier composto de casamento (menor = mais forte) — ver cabeçalho.
  static int _tier(
      GeocodingResult r, String q, String brandHead, List<String> hints) {
    final n = _name(r);
    if (q.isNotEmpty && n == q) return 0;
    final brand = _brandMatches(r, brandHead);
    final loc = _locationMatches(r, hints);
    if (brand && loc) return 1;
    if (brand) return 2;
    if (loc) return 3;
    if (q.isNotEmpty && n.startsWith(q)) return 4;
    if (q.isNotEmpty && n.contains(q)) return 5;
    return 6;
  }

  // Marca casa quando o nome contém a cabeça da marca (discriminador principal).
  static bool _brandMatches(GeocodingResult r, String brandHead) =>
      brandHead.isNotEmpty && _name(r).contains(brandHead);

  // Local casa quando ALGUM hint aparece em city/district/state/displayName/address.
  static bool _locationMatches(GeocodingResult r, List<String> hints) {
    if (hints.isEmpty) return false;
    final fields = [r.city, r.state, r.displayName, r.address].map(_norm).toList();
    for (final h in hints) {
      if (fields.any((f) => f.contains(h))) return true;
    }
    return false;
  }

  // Genérica = só categoria, sem núcleo de marca (ex.: "Mercado", "Farmácia").
  static bool _isGeneric(String? brandHint, String? categoryHint) =>
      categoryHint != null &&
      (brandHint == null || brandHint.trim().isEmpty);

  // ── Helpers públicos (também usados pelo DecisionEngine) ──────────────────

  // Distância em metros entre dois candidatos.
  static double distanceBetween(GeocodingResult a, GeocodingResult b) =>
      _haversine(a.lat, a.lon, b.lat, b.lon);

  // True quando os dois candidatos têm o MESMO nome (normalizado, não vazio).
  static bool sameName(GeocodingResult a, GeocodingResult b) {
    final na = _name(a);
    final nb = _name(b);
    return na.isNotEmpty && na == nb;
  }

  // True quando o nome do candidato é EXATAMENTE igual à consulta (normalizado).
  static bool nameEquals(GeocodingResult r, String query) {
    final n = _name(r);
    return n.isNotEmpty && n == _norm(query);
  }

  // Nome normalizado do candidato (primeira linha do displayName se não houver name).
  static String _name(GeocodingResult r) =>
      _norm(r.name.isNotEmpty ? r.name : r.displayName.split('\n').first);

  // Primeiro token normalizado de uma string (cabeça da marca).
  static String _headToken(String? s) {
    if (s == null) return '';
    final t = _norm(s).split(RegExp(r'\s+'));
    return t.isEmpty ? '' : t.first;
  }

  // Normaliza para comparação: minúscula, sem acento, trim.
  static String _norm(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[áàãâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòõôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');

  // Distância em metros entre dois pontos (Haversine). Só para desempate.
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // raio da Terra em metros
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
