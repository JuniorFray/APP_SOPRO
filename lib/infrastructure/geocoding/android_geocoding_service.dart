import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/core/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/daos/geocoding_cache_dao.dart';
import 'geocoding_platform_interface.dart';
import 'query_normalizer.dart';
import 'search_strategy.dart';
import 'candidate_filter.dart';
import 'location_ranker.dart';

// Busca em cascata para Android:
//   CAMADA 1 — Cache local SQLite (zero custo, zero latência)
//   CAMADA 2 — Geocoder nativo Android via MethodChannel (grátis, sem cota)
//   CAMADA 3 — Photon/OSM via HTTP (grátis, sem API key)
//
// Cada resultado bem-sucedido é salvo no cache antes de ser retornado,
// garantindo que chamadas futuras com a mesma query sejam servidas localmente.
//
// Etapa 1 — nova arquitetura de resolução de localização:
//   QueryNormalizer classifica → SearchStrategy escolhe provedor/viés → esta
//   classe executa → LocationRanker ordena. A classificação e a estratégia,
//   antes internas (enum SearchType + _classifyQuery), viraram componentes puros.

class AndroidGeocodingService implements GeocodingPlatformInterface {
  static const _channel = MethodChannel('com.sopro.sopro/geocoder');
  static const _uuid = Uuid();

  // Photon location_bias_scale (0.0–1.0). Peso da proximidade sobre a prominência.
  static const _locationBiasScale = '0.5';

  // Zoom da location bias no Stage 2 (Photon `zoom`, default 12). 16 ≈ nível de
  // bairro: raio pequeno em torno do ponto do locationHint resolvido no Stage 1.
  static const _neighborhoodZoom = '16';

  // Layers de LUGAR usados no Stage 1 (resolver o bairro/cidade do locationHint).
  // Sem osm_tag → busca administrativa pura, nunca POIs.
  static const _placeLayers = ['district', 'locality', 'city', 'county', 'state'];

  final GeocodingCacheDao _cacheDao;

  AndroidGeocodingService(this._cacheDao);

  // ── Forward geocoding ─────────────────────────────────────────────────────

  @override
  Future<List<GeocodingResult>> search(String query) async {
    // 1. Normalização — só classifica (QueryNormalizer, componente puro).
    final normalized = QueryNormalizer.normalize(query);
    // TEMP remover após validação do Ranker.
    Logger.debug('query_normalized',
        payload: {'query': normalized.query, 'kind': normalized.kind.name},
        feature: 'geocoding', action: 'normalize');
    // TEMP remover após validação do DecisionEngine
    Logger.debug('query_hints_detected', payload: {
      'brand':     normalized.brandHint,
      'locations': normalized.locationHints,
      'category':  normalized.categoryHint,
    }, feature: 'geocoding', action: 'hints');

    // Chave de cache PREFIXADA pelo tipo → não reutiliza entradas do algoritmo
    // antigo (ex.: "piracicaba" vs "city:piracicaba"). Cache não é apagado.
    final key = _normalizeKey(normalized.query, normalized.kind);

    // Lê localização do usuário (viés/distância) — usada conforme a estratégia.
    final prefs   = await SharedPreferences.getInstance();
    final userLat = await _readCoord(prefs, 'last_known_lat');
    final userLon = await _readCoord(prefs, 'last_known_lon');

    // 2. Estratégia — provedor + constraints (SearchStrategy, componente puro).
    //    Computada antes do cache para orientar também o CandidateFilter.
    final strategy = SearchStrategy.plan(normalized.kind);
    final constraints = strategy.constraints;
    // TEMP remover após validação.
    Logger.debug('search_constraints', payload: {
      'provider':    strategy.provider.name,
      'constraints': constraints.toLog(),
    }, feature: 'geocoding', action: 'constraints');

    // Camada 1: cache local (apenas resultados com qualidade suficiente).
    final cached = await _cacheDao.findByKey(key);
    final qualityCached = cached
        .where((row) => _isQualityResult(GeocodingResult(
              displayName: row.displayName,
              lat: row.lat,
              lon: row.lon,
              source: row.source,
            )))
        .map((row) => GeocodingResult(
              displayName: row.displayName,
              lat: row.lat,
              lon: row.lon,
              source: row.source,
              hasNumber: _addressHasNumber(row.displayName),
            ))
        .toList();
    if (qualityCached.isNotEmpty) {
      return _filterAndRank(normalized, constraints, qualityCached, userLat, userLon);
    }

    // 3. Execução — Photon (constraints) ou Geocoder nativo (fallback Photon).
    final List<GeocodingResult> raw;
    switch (strategy.provider) {
      case SearchProvider.photon:
        // Busca em DOIS ESTÁGIOS só quando há locationHint (estabelecimento
        // qualificado por bairro). Sem hint → caminho simples de sempre.
        if (normalized.locationHints.isNotEmpty) {
          raw = await _twoStageSearch(
              normalized, constraints, key, userLat, userLon);
        } else {
          raw = await _searchPhoton(query, key, constraints,
              userLat: userLat, userLon: userLon);
        }
      case SearchProvider.geocoder:
        raw = await _searchGeocoderThenPhoton(
            query, key, constraints, userLat, userLon);
    }

    // 4. CandidateFilter → LocationRanker.
    return _filterAndRank(normalized, constraints, raw, userLat, userLon);
  }

  // Estágio B: filtra candidatos inválidos e emite os logs temporários; depois
  // rankeia apenas os sobreviventes. Cache e busca fresca passam pelo mesmo caminho.
  List<GeocodingResult> _filterAndRank(
      NormalizedQuery normalized, SearchConstraints c,
      List<GeocodingResult> raw, double userLat, double userLon) {
    // TEMP remover após validação.
    Logger.debug('candidate_filter_started', payload: {'received': raw.length},
        feature: 'geocoding', action: 'filter');
    final filtered = CandidateFilter.filter(
      raw,
      queryType: c.queryType,
      countryCode: c.countryCode,
      radiusKm: c.radiusKm,
      userLat: userLat == 0.0 ? null : userLat,
      userLon: userLon == 0.0 ? null : userLon,
    );
    for (final rem in filtered.removed) {
      // TEMP remover após validação.
      Logger.debug('candidate_filter_removed', payload: {
        'candidate': rem.candidate.displayName.split('\n').first,
        'reason':    rem.reason,
      }, feature: 'geocoding', action: 'filter');
    }
    // TEMP remover após validação.
    Logger.debug('candidate_filter_finished', payload: {
      'kept':    filtered.kept.length,
      'removed': filtered.removed.length,
    }, feature: 'geocoding', action: 'filter');
    return _rankAndLog(normalized, filtered.kept, userLat, userLon);
  }

  // Aplica o LocationRanker e emite os logs temporários de auditoria do Ranker.
  List<GeocodingResult> _rankAndLog(
      NormalizedQuery normalized, List<GeocodingResult> raw,
      double userLat, double userLon) {
    final rr = LocationRanker.rank(
      normalized.query, raw,
      userLat: userLat == 0.0 ? null : userLat,
      userLon: userLon == 0.0 ? null : userLon,
      brandHint: normalized.brandHint,
      locationHints: normalized.locationHints,
      categoryHint: normalized.categoryHint,
    );
    final ranked = rr.orderedCandidates;
    // TEMP remover após validação.
    if (normalized.locationHints.isNotEmpty) {
      final hints = normalized.locationHints.map((h) => h.toLowerCase()).toList();
      for (final r in ranked) {
        final d = r.district.toLowerCase();
        Logger.debug('district_match', payload: {
          'candidate': r.name.isNotEmpty ? r.name : r.displayName.split('\n').first,
          'matched':   d.isNotEmpty && hints.any((h) => d.contains(h)),
        }, feature: 'geocoding', action: 'district_match');
      }
    }
    // TEMP remover após validação do Ranker.
    Logger.debug('ranking_result', payload: {
      'query': normalized.query,
      'ordered_candidates':
          ranked.map((r) => r.displayName.split('\n').first).toList(),
    }, feature: 'geocoding', action: 'rank');
    // TEMP remover após validação do Ranker.
    Logger.debug('ranking_selected', payload: {
      'first':  ranked.isNotEmpty ? ranked.first.displayName.split('\n').first : '',
      'second': ranked.length > 1 ? ranked[1].displayName.split('\n').first : '',
      'auto_selected': rr.confidence == LocationConfidence.high,
    }, feature: 'geocoding', action: 'rank');
    return ranked;
  }

  // ── Busca em dois estágios (estabelecimento + bairro) ─────────────────────
  // Só chamada quando normalized.locationHints não é vazio. Stage 1 resolve o
  // bairro/cidade do hint em coordenadas; Stage 2 busca a MARCA (sem o hint no
  // q) com viés geográfico real (lat/lon do Stage 1 + zoom de bairro). Se o
  // Stage 1 não resolver, cai no comportamento antigo (texto livre no q).
  Future<List<GeocodingResult>> _twoStageSearch(
      NormalizedQuery normalized, SearchConstraints c, String key,
      double userLat, double userLon) async {
    // TEMP remover após validação.
    Logger.debug('two_stage_search_started', payload: {
      'brand':        normalized.brandHint,
      'locationHint': normalized.locationHints,
    }, feature: 'geocoding', action: 'two_stage_start');

    // Stage 1 — resolve o locationHint num lugar administrativo real.
    final place =
        await _resolveLocationHint(normalized.locationHints, c.countryCode);
    if (place == null) {
      // Não resolveu o bairro → comportamento antigo (q com o texto todo).
      return _searchPhoton(normalized.query, key, c,
          userLat: userLat, userLon: userLon);
    }
    // TEMP remover após validação.
    Logger.debug('location_hint_resolved', payload: {
      'hint':     place.hint,
      'district': place.district,
      'city':     place.city,
      'lat':      place.lat,
      'lon':      place.lon,
    }, feature: 'geocoding', action: 'hint_resolved');

    // Marca sem o hint: remove o sufixo do bairro do brandHint (é sufixo por
    // construção do QueryNormalizer). "Assaí Gonzaga" − "Gonzaga" → "Assaí".
    final brandOnly = _stripHintSuffix(normalized.brandHint, place.hint);

    // Stage 2 — busca a marca com viés no ponto do Stage 1 (zoom de bairro).
    final raw = await _searchPhoton(brandOnly, key, c,
        userLat: place.lat, userLon: place.lon, zoom: _neighborhoodZoom);
    // TEMP remover após validação.
    Logger.debug('two_stage_search_finished', payload: {'candidates': raw.length},
        feature: 'geocoding', action: 'two_stage_finish');
    return raw;
  }

  // Stage 1: tenta cada locationHint (do mais específico ao mais curto) como
  // busca de LUGAR (layers administrativos, sem osm_tag) e devolve o primeiro
  // que resolver. Reusa _searchPhoton — o parser já popula district/city/coords.
  Future<_ResolvedPlace?> _resolveLocationHint(
      List<String> hints, String? countryCode) async {
    final placeConstraints = SearchConstraints(
      queryType: QueryKind.city,
      countryCode: countryCode,
      layers: _placeLayers,
    );
    for (final hint in hints) {
      final placeKey = _normalizeKey(hint, QueryKind.city);
      final res = await _searchPhoton(hint, placeKey, placeConstraints);
      if (res.isNotEmpty) {
        final f = res.first;
        return _ResolvedPlace(
          hint:     hint,
          lat:      f.lat,
          lon:      f.lon,
          district: f.district,
          city:     f.city,
        );
      }
    }
    return null;
  }

  // Remove o hint (sufixo) do brandHint, devolvendo só a marca. Se sobrar vazio
  // ou o hint não for sufixo, devolve o brandHint inteiro (fallback seguro).
  String _stripHintSuffix(String? brand, String hint) {
    final b = (brand ?? '').trim();
    final h = hint.trim();
    if (b.isEmpty) return h;
    if (b.toLowerCase().endsWith(h.toLowerCase())) {
      final cut = b.substring(0, b.length - h.length).trim();
      if (cut.isNotEmpty) return cut;
    }
    return b;
  }

  // Camadas 2 + 3: Geocoder nativo Android (bounding box do usuário) e, se vazio
  // ou indisponível, fallback Photon. Comportamento idêntico ao fluxo anterior.
  Future<List<GeocodingResult>> _searchGeocoderThenPhoton(
      String query, String key, SearchConstraints constraints,
      double userLat, double userLon) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'searchAddress', {
            'query':   query,
            'userLat': userLat,
            'userLon': userLon,
          });
      if (raw != null && raw['found'] == true) {
        final rawList = raw['results'] as List<Object?>? ?? [];
        final results = rawList
            .whereType<Map<Object?, Object?>>()
            .map((item) {
              final address = item['returned_address'] as String? ?? '';
              final name    = item['name']  as String? ?? '';
              final city    = item['city']  as String? ?? '';
              final state   = item['state'] as String? ?? '';
              return GeocodingResult(
                displayName: _buildDisplayName(address, name, city, state),
                lat:       (item['lat'] as num?)?.toDouble() ?? 0.0,
                lon:       (item['lon'] as num?)?.toDouble() ?? 0.0,
                source:    'geocoder_native',
                hasNumber: item['has_number'] as bool? ?? false,
                // Campos enriquecidos (Etapa 1 — insumo do LocationRanker).
                name:    name,
                address: address,
                city:    city,
                state:   state,
              );
            })
            .where((r) => r.displayName.isNotEmpty && r.lat != 0.0)
            .toList();
        final qualityResults = results.where(_isQualityResult).toList();
        if (qualityResults.isNotEmpty) {
          await _saveToCache(qualityResults, key);
          return qualityResults;
        }
      }
    } catch (e, st) {
      // Geocoder indisponível (emulador sem Google Play) — cai para Photon
      Logger.debug('geocoder_native_failed', payload: {'query': query},
          exception: e, stackTrace: st, feature: 'geocoding', action: 'native');
    }
    // Fallback Photon (endereço é local → mantém viés de lat/lon + constraints).
    return _searchPhoton(query, key, constraints,
        userLat: userLat, userLon: userLon);
  }

  // ── Reverse geocoding ─────────────────────────────────────────────────────

  @override
  Future<GeocodingResult?> reverse(double lat, double lon) async {
    // Chave de cache para reverse: "rev:{lat5d}:{lon5d}"
    final key =
        'rev:${lat.toStringAsFixed(5)}:${lon.toStringAsFixed(5)}';

    // Cache local
    final cached = await _cacheDao.findByKey(key);
    if (cached.isNotEmpty) {
      final row = cached.first;
      return GeocodingResult(
        displayName: row.displayName,
        lat: row.lat,
        lon: row.lon,
        source: row.source,
      );
    }

    // Geocoder nativo Android via reverseGeocode
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'reverseGeocode', {'lat': lat, 'lon': lon});
      if (raw != null) {
        final found = raw['found'] as bool? ?? false;
        if (found) {
          final displayName = raw['display_name'] as String? ??
              raw['returned_address'] as String? ??
              'Local desconhecido';
          final result = GeocodingResult(
            displayName: displayName,
            lat: lat,
            lon: lon,
            source: 'geocoder_native',
          );
          await _saveToCache([result], key);
          return result;
        }
      }
    } catch (e, st) {
      Logger.debug('geocoder_reverse_failed',
          exception: e, stackTrace: st, feature: 'geocoding', action: 'reverse');
    }

    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // Lê coordenada com fallback: Double → String → 0.0
  Future<double> _readCoord(SharedPreferences prefs, String key) async {
    final d = prefs.getDouble(key);
    if (d != null && d != 0.0) return d;
    final s = prefs.getString(key);
    if (s != null) return double.tryParse(s) ?? 0.0;
    return 0.0;
  }

  // Rejeita resultados que contêm apenas cidade/estado/país sem rua ou estabelecimento
  bool _isQualityResult(GeocodingResult r) {
    final d = r.displayName.toLowerCase();
    final cityOnlyPatterns = [
      RegExp(r'^[^,]+,\s*(SP|RJ|MG|RS|PR|SC|BA|CE|PE|GO|AM|PA|MT|MS|DF|ES|MA|PB|PI|RN|AL|SE|RO|AC|AP|RR|TO)\s*,?\s*brasil\s*$', caseSensitive: false),
      RegExp(r'^[^,]+,\s*(SP|RJ|MG|RS|PR|SC|BA|CE|PE|GO|AM|PA|MT|MS|DF|ES|MA|PB|PI|RN|AL|SE|RO|AC|AP|RR|TO)\s*,?\s*(brasil)?\s*$', caseSensitive: false),
    ];
    return !cityOnlyPatterns.any((p) => p.hasMatch(d));
  }

  // Normaliza a chave de cache: "{tipo}:{query sem acento, minúscula}". O prefixo
  // de tipo separa entradas do algoritmo antigo (sem prefixo) das novas — evita
  // reutilizar resultados incorretos criados antes da classificação.
  String _normalizeKey(String query, QueryKind kind) {
    final normalized = query
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c');
    return '${kind.name}:$normalized';
  }

  // Monta o displayName. Quando há nome de estabelecimento (featureName) e ele
  // não é redundante com o endereço, prefixa o nome numa linha acima:
  //   "Assaí Atacadista\nAv. Presidente Kennedy, 1234"
  // Endereço residencial (sem nome real) mantém só o endereço.
  String _buildDisplayName(
      String address, String name, String city, String state) {
    // Sem endereço: usa nome + cidade + estado (comportamento original)
    if (address.isEmpty) {
      return [name, city, state].where((s) => s.isNotEmpty).join(', ');
    }
    // Com endereço: prefixa o nome quando existir e não for redundante
    if (name.isNotEmpty && !_nameIsRedundant(name, address)) {
      return '$name\n$address';
    }
    return address;
  }

  // Nome é redundante quando vazio, igual ao endereço ou já contido nele
  // (ex.: featureName = número da rua "1234" já presente em "Rua X, 1234").
  bool _nameIsRedundant(String name, String address) {
    final n = name.toLowerCase().trim();
    final a = address.toLowerCase();
    return n.isEmpty || n == a || a.contains(n);
  }

  // Chama a API Photon (OSM) aplicando os SearchConstraints como parâmetros
  // OFICIAIS: countrycode (filtro de país), layer (tipo de feature), osm_tag
  // (restringe a POIs), lat/lon + location_bias_scale (viés). bbox do Brasil é
  // mantido como salvaguarda adicional.
  Future<List<GeocodingResult>> _searchPhoton(
      String query, String key, SearchConstraints c,
      {double userLat = 0.0, double userLon = 0.0, String? zoom}) async {
    Logger.debug('photon_called', payload: {'query': query},
        feature: 'geocoding', action: 'photon_start');
    final sw = Stopwatch()..start();
    try {
      // Remove sufixos numéricos do debounce (ex: ", 52") e monta URL com encoding correto
      final cleanQuery = query.replaceAll(RegExp(r'\s*,\s*\d+\s*$'), '').trim();
      // Map<String, dynamic>: valores List<String> viram chaves repetidas na URL
      // (ex.: layer=city&layer=locality) — exatamente como o Photon espera.
      final params = <String, dynamic>{
        'q':     cleanQuery,
        'limit': '5',
        'bbox':  '-73.9,-33.7,-34.7,5.3',
      };
      if (c.countryCode != null) params['countrycode'] = c.countryCode!;
      if (c.layers.isNotEmpty) params['layer'] = c.layers;
      if (c.osmTags.isNotEmpty) params['osm_tag'] = c.osmTags;
      if (c.useBias && userLat != 0.0 && userLon != 0.0) {
        params['lat'] = userLat.toString();
        params['lon'] = userLon.toString();
        params['location_bias_scale'] = _locationBiasScale;
        // zoom = raio da location bias (Photon api-v1, default 12). Valor maior →
        // raio menor → viés mais forte no ponto. Usado no Stage 2 (bairro).
        if (zoom != null) params['zoom'] = zoom;
      }
      final uri = Uri.https('photon.komoot.io', '/api/', params);

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Sopro/1.0 (Android; komoot-photon-client)');
      final response = await request.close();

      if (response.statusCode != 200) {
        Logger.warn('photon_http_error', payload: {
          'query':  query,
          'status': response.statusCode,
        }, feature: 'geocoding', action: 'photon_http', durationMs: sw.elapsedMilliseconds);
        return [];
      }

      final body = await response.transform(const Utf8Decoder()).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? [];

      final results = features
          .map((f) => _parsePhotonFeature(f as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();

      Logger.debug('photon_result', payload: {
        'query':          query,
        'features_raw':   features.length,
        'results_parsed': results.length,
        'first_parsed':   results.isNotEmpty ? results.first.displayName : 'nenhum',
      }, feature: 'geocoding', action: 'photon_parse', durationMs: sw.elapsedMilliseconds);

      if (results.isNotEmpty) {
        await _saveToCache(results, key);
      }

      return results;
    } catch (e, st) {
      Logger.error('photon_error', payload: {'query': query},
          exception: e, stackTrace: st,
          feature: 'geocoding', action: 'photon_call',
          durationMs: sw.elapsedMilliseconds);
      return [];
    }
  }

  // Converte uma feature GeoJSON do Photon em GeocodingResult
  GeocodingResult? _parsePhotonFeature(Map<String, dynamic> feature) {
    try {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.length < 2) return null;

      final lon = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();

      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final name    = props['name']    as String? ?? '';
      final street  = props['street']  as String? ?? '';
      final housen  = props['housenumber'] as String? ?? '';
      final city    = props['city']    as String? ?? props['town'] as String? ?? '';
      // Bairro/suburb — Photon devolve em `district` (doc oficial api-v1). Era
      // descartado; agora vira insumo de matching do locationHint no Ranker.
      final district = props['district'] as String? ?? '';
      final state   = props['state']   as String? ?? '';
      final country = props['country'] as String? ?? '';
      final postal  = props['postcode'] as String? ?? '';
      final type    = props['type']    as String? ?? ''; // house/street/city/...

      // Monta a linha de endereço (rua + número, cidade, estado)
      final addrParts = <String>[];
      if (street.isNotEmpty) {
        addrParts.add(housen.isNotEmpty ? '$street, $housen' : street);
      }
      if (city.isNotEmpty) addrParts.add(city);
      if (state.isNotEmpty) addrParts.add(state);
      final address = addrParts.join(' — ');

      // Prefixa o nome do estabelecimento quando existir e não for redundante;
      // nunca perde o name (sem endereço, o próprio name vira o displayName)
      final String displayName;
      if (name.isNotEmpty && address.isNotEmpty &&
          !_nameIsRedundant(name, address)) {
        displayName = '$name\n$address';
      } else if (address.isNotEmpty) {
        displayName = address;
      } else {
        displayName = name;
      }
      if (displayName.isEmpty) return null;

      return GeocodingResult(
        displayName: displayName,
        lat: lat,
        lon: lon,
        source: 'photon',
        hasNumber: housen.isNotEmpty,
        // Campos enriquecidos (Etapa 1 — insumo do LocationRanker).
        name:        name,
        address:     address,
        district:    district,
        city:        city,
        state:       state,
        country:     country,
        postalCode:  postal,
        featureType: type,
      );
    } catch (e, st) {
      Logger.debug('photon_feature_parse_failed',
          exception: e, stackTrace: st, feature: 'geocoding', action: 'photon_parse');
      return null;
    }
  }

  // Persiste lista de resultados no cache com a chave normalizada
  Future<void> _saveToCache(List<GeocodingResult> results, String key) async {
    final entries = results
        .map((r) => _cacheDao.buildEntry(
              id: _uuid.v4(),
              queryKey: key,
              displayName: r.displayName,
              lat: r.lat,
              lon: r.lon,
              source: r.source,
            ))
        .toList();
    await _cacheDao.saveAll(entries);
  }

  // Heurística: o endereço possui número se contiver dígito precedido de vírgula/espaço
  bool _addressHasNumber(String address) =>
      RegExp(r'[,\s]\d+').hasMatch(address);
}

// Resultado do Stage 1: o lugar do locationHint resolvido em coordenadas.
class _ResolvedPlace {
  final String hint;      // Hint que resolveu (ex.: "Gonzaga", "Praia Grande")
  final double lat;
  final double lon;
  final String district;  // Bairro, quando o Photon o classificou como district
  final String city;      // Município do lugar resolvido
  const _ResolvedPlace({
    required this.hint,
    required this.lat,
    required this.lon,
    required this.district,
    required this.city,
  });
}
