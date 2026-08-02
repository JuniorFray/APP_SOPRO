import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/core/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

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
  static const _locationBiasScale = '0.9';

  // Zoom quando o viés é recentrado numa CIDADE citada (ex.: "farmácia são
  // paulo"): 11 ≈ nível de cidade — raio amplo o bastante pra cobrir o município.
  // (Photon `zoom`, default 12; maior = raio menor.)
  static const _cityZoom = '11';

  // Modificadores de categoria que podem aparecer no final do nome.
  // Ex.: "Assaí Atacadista" → strip "Atacadista" → busca "Assaí".
  // "Delta Supermercado" → strip "Supermercado" → busca "Delta".
  static const _categoryModifiers = {
    'atacadista', 'atacado', 'supermercado', 'supermercados',
    'hipermercado', 'hipermercados', 'mercado', 'drogaria',
    'farmacia', 'farmacias', 'hospital', 'clinica',
    'restaurante', 'lanchonete', 'padaria', 'academia',
    'comercio', 'comercial', 'distribuidora',
  };

  // Layers de LUGAR usados no Stage 1 (resolver o bairro/cidade do locationHint).
  // Sem osm_tag → busca administrativa pura, nunca POIs.
  static const _placeLayers = ['district', 'locality', 'city', 'county', 'state'];

  final GeocodingCacheDao _cacheDao;

  AndroidGeocodingService(this._cacheDao);

  // ── Forward geocoding ─────────────────────────────────────────────────────

  @override
  Future<List<GeocodingResult>> search(String rawQuery) async {
    // Endereços BR: "Av Paulista 1000" → "Av Paulista número 1000" (paridade com
    // a forma que o Photon resolve). Ver _insertHouseNumberKeyword.
    final query = _insertHouseNumberKeyword(rawQuery);
    // 1. Normalização — só classifica (QueryNormalizer, componente puro).
    final normalized = QueryNormalizer.normalize(query);

    // Chave de cache PREFIXADA pelo tipo → não reutiliza entradas do algoritmo
    // antigo (ex.: "piracicaba" vs "city:piracicaba"). Cache não é apagado.
    final key = _normalizeKey(normalized.query, normalized.kind);

    // Lê localização do usuário (viés/distância) — usada conforme a estratégia.
    final prefs   = await SharedPreferences.getInstance();
    final userLat = await _readCoord(prefs, 'last_known_lat');
    final userLon = await _readCoord(prefs, 'last_known_lon');

    // 2. Estratégia — provedor + constraints (SearchStrategy, componente puro).
    //    Computada antes do cache para orientar também o CandidateFilter.
    final strategy = SearchStrategy.plan(normalized);
    final constraints = strategy.constraints;

    // Viés desligado silenciosamente (sem last_known) vira busca global — o
    // chamador deveria aquecer o GPS antes. Log pontual para auditar em campo.
    if (constraints.useBias && (userLat == 0.0 || userLon == 0.0)) {
      Logger.warn('geocoding_bias_off', payload: {
        'query': normalized.query,
        'kind':  normalized.kind.name,
      }, feature: 'geocoding', action: 'bias_gate');
    }

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
    // Estabelecimento é sensível a viés/proximidade (e pode recentrar numa
    // cidade citada) — a chave de cache é só texto, então servir do cache com o
    // centro do usuário daria resultado incoerente. Cache-read só p/ tipos
    // com coordenada absoluta (cidade/estado/endereço).
    if (qualityCached.isNotEmpty && normalized.kind != QueryKind.establishment) {
      return _filterAndRank(normalized, constraints, qualityCached, userLat, userLon);
    }

    // 3. Execução — Photon (constraints) ou Geocoder nativo (fallback Photon).
    //    Estabelecimento pode RECENTRAR o viés numa cidade citada (ver
    //    _searchEstablishmentRaw); os demais tipos usam o ponto do usuário.
    List<GeocodingResult> raw;
    double biasLat = userLat, biasLon = userLon;
    switch (strategy.provider) {
      case SearchProvider.photon:
        if (normalized.kind == QueryKind.establishment) {
          final est = await _searchEstablishmentRaw(
              normalized, constraints, key, userLat, userLon);
          raw = est.raw;
          biasLat = est.lat;
          biasLon = est.lon;
        } else {
          raw = await _searchPhoton(query, key, constraints,
              userLat: userLat, userLon: userLon);
        }
      case SearchProvider.geocoder:
        raw = await _searchGeocoderThenPhoton(
            query, key, constraints, userLat, userLon);
    }

    // 4. CandidateFilter → LocationRanker (centrado no viés efetivo).
    final primary = _filterAndRank(
        normalized, constraints, raw, biasLat, biasLon);
    if (primary.isNotEmpty) return primary;

    // 5. LocationIQ — acionado quando Photon retornou vazio OU
    //    quando retornou candidatos que o CandidateFilter descartou
    //    (ex.: mesmo nome em outra cidade, distância > radiusKm).
    //    Usa query com marca limpa para melhorar precisão:
    //      "Açaí Atacadista Piracicaba" → busca "Açaí Atacadista Piracicaba"
    //      "Delta Supermercado"         → busca "Delta"
    final rawBrand = normalized.brandHint ?? query;
    final cleanBrand = _stripTrailingCategoryWords(rawBrand);
    final liqHints = normalized.locationHints;
    // Query base: marca limpa + último hint de localização (se houver).
    String liqQuery = liqHints.isNotEmpty
        ? '$cleanBrand ${liqHints.last}'
        : (cleanBrand.isNotEmpty ? cleanBrand : query);
    // Injeção automática de cidade para queries curtas (≤2 tokens) sem hint de
    // localização explícito. Ex.: "Assaí" → "Assaí Piracicaba". Evita que o
    // LocationIQ busque no Brasil inteiro sem contexto geográfico.
    if (liqHints.isEmpty &&
        normalized.kind == QueryKind.establishment &&
        userLat != 0.0 && userLon != 0.0) {
      // Base a enriquecer com a cidade. Categoria pura ("hospital", "farmácia",
      // "academia") não tem marca; se _stripTrailingCategoryWords zerar a base,
      // usa a query crua para não perder a palavra da categoria — senão a busca
      // ficaria só " <cidade>", sem o QUÊ procurar.
      final base = cleanBrand.isNotEmpty ? cleanBrand : query;
      final baseTokens = base
          .trim()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .length;
      if (baseTokens <= 2) {
        // Mesmo mecanismo do estabelecimento com marca: reverse geocoding
        // cacheado (last_known_city) via _getUserCity().
        final city = await _getUserCity(userLat, userLon);
        if (city.isNotEmpty) {
          liqQuery = '$base $city';
          Logger.debug('locationiq_city_injected', payload: {
            'original': base,
            'enriched': liqQuery,
            'city':     city,
          }, feature: 'geocoding', action: 'city_inject');
        }
      }
    }
    final liqRaw = await _searchLocationIQ(
        liqQuery, key,
        userLat: userLat, userLon: userLon);
    return _filterAndRank(
        normalized, constraints, liqRaw, userLat, userLon);
  }

  // Estágio B: filtra candidatos inválidos e rankeia apenas os sobreviventes.
  // Cache e busca fresca passam pelo mesmo caminho.
  List<GeocodingResult> _filterAndRank(
      NormalizedQuery normalized, SearchConstraints c,
      List<GeocodingResult> raw, double userLat, double userLon) {
    final filtered = CandidateFilter.filter(
      raw,
      queryType: c.queryType,
      countryCode: c.countryCode,
      radiusKm: c.radiusKm,
      userLat: userLat == 0.0 ? null : userLat,
      userLon: userLon == 0.0 ? null : userLon,
    );
    return _rankAndLog(normalized, filtered.kept, userLat, userLon);
  }

  // Aplica o LocationRanker e devolve os candidatos ordenados por confiança.
  // Categoria genérica ("farmácia") ranqueia por PROXIMIDADE primeiro (senão um
  // POI homônimo de alta prominência longe ganharia do vizinho — sintoma 1/2).
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
      proximityPrimary: normalized.isGenericCategory,
    );
    return rr.orderedCandidates;
  }

  // ── Busca de estabelecimento ──────────────────────────────────────────────
  // Devolve os candidatos crus + o CENTRO do viés efetivo (usado no filtro/rank).
  // Se a consulta cita uma cidade/bairro resolvível (locationHints), RECENTRA o
  // viés nesse lugar e busca só a marca/categoria lá — nunca deixa o nome da
  // cidade virar texto de nome pesquisado (corrige "drogaria são paulo"). Sem
  // contexto de local, busca o texto todo em torno do usuário.
  Future<({List<GeocodingResult> raw, double lat, double lon})>
      _searchEstablishmentRaw(NormalizedQuery normalized, SearchConstraints c,
          String key, double userLat, double userLon) async {
    double biasLat = userLat, biasLon = userLon;
    String queryText = normalized.query;
    String? zoom;

    if (normalized.locationHints.isNotEmpty) {
      // Stage 1 — resolve o hint (mais longo primeiro) num lugar administrativo.
      final place =
          await _resolveLocationHint(normalized.locationHints, c.countryCode);
      if (place != null) {
        biasLat = place.lat;
        biasLon = place.lon;
        zoom = _cityZoom; // viés de cidade em torno do ponto resolvido
        bool sameTxt(String a, String b) =>
            a.trim().toLowerCase() == b.trim().toLowerCase();
        // Marca sem o lugar. Quando o que sobra É o próprio lugar (a "marca" era
        // a cidade, ex.: "farmácia são paulo" → brand "são paulo" == hint), a
        // busca é de CATEGORIA no lugar → usa a categoria; o osm_tag filtra por
        // tipo. Senão, busca a marca real ("Assaí Gonzaga" → "Assaí").
        final brandOnly = _stripHintSuffix(normalized.brandHint, place.hint);
        final brandIsPlace = brandOnly.trim().isEmpty ||
            sameTxt(brandOnly, place.hint) ||
            sameTxt(brandOnly, normalized.brandHint ?? '');
        queryText = brandIsPlace
            ? (normalized.categoryHint ?? normalized.query)
            : brandOnly;
      }
    }

    final raw = await _searchPhoton(queryText, key, c,
        userLat: biasLat, userLon: biasLon, zoom: zoom);
    return (raw: raw, lat: biasLat, lon: biasLon);
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
    String result = b;
    if (result.toLowerCase().endsWith(h.toLowerCase())) {
      final cut = result.substring(0, result.length - h.length).trim();
      if (cut.isNotEmpty) result = cut;
    }
    // Remove modificadores de categoria que sobraram após strip do hint.
    // Ex.: "Açaí Atacadista" (após remover "Piracicaba") → "Açaí".
    final stripped = _stripTrailingCategoryWords(result);
    return stripped.isNotEmpty ? stripped : result;
  }

  // Remove palavras de categoria do final da marca.
  // Preserva sempre ao menos o primeiro token.
  // Ex.: "Açaí Atacadista" → "Açaí"
  //      "Delta Supermercado" → "Delta"
  //      "Pão de Açúcar" → "Pão de Açúcar" (sem modificador)
  String _stripTrailingCategoryWords(String brand) {
    String normLocal(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c');
    final tokens = brand.trim().split(RegExp(r'\s+'));
    var end = tokens.length;
    while (end > 1 &&
        _categoryModifiers.contains(normLocal(tokens[end - 1]))) {
      end--;
    }
    return tokens.sublist(0, end).join(' ');
  }

  // Rótulo "Bairro, Cidade" das coordenadas (reverse Photon), cacheado. Só a
  // cidade quando o OSM não traz bairro. Usado pelo card de clima — o OWM rotula
  // pela estação mais próxima e às vezes erra a cidade/bairro.
  Future<String> userPlaceLabel(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('last_known_place') ?? '';
    if (cached.isNotEmpty) return cached;
    final p = await _photonReverse(lat, lon);
    if (p.city.isEmpty) return '';
    final label = p.district.isNotEmpty ? '${p.district}, ${p.city}' : p.city;
    await prefs.setString('last_known_place', label);
    return label;
  }

  // Retorna só o MUNICÍPIO do usuário (reverse Photon), cacheado. Usado no viés
  // de busca forward — comportamento inalterado (só a cidade).
  Future<String> _getUserCity(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('last_known_city') ?? '';
    if (cached.isNotEmpty) return cached;
    final p = await _photonReverse(lat, lon);
    if (p.city.isNotEmpty) await prefs.setString('last_known_city', p.city);
    return p.city;
  }

  // Reverse geocoding puro via Photon → (cidade, bairro). Sem cache; cada
  // chamador cacheia como precisa. Vazio em erro/rede/sem resultado.
  Future<({String city, String district})> _photonReverse(
      double lat, double lon) async {
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'limit': '1',
      });
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Sopro/1.0');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(const Utf8Decoder()).join();
        client.close();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final features = json['features'] as List<dynamic>? ?? [];
        if (features.isNotEmpty) {
          final props = (features.first
              as Map<String, dynamic>)['properties']
              as Map<String, dynamic>? ?? {};
          final city = (props['city'] as String?) ??
              (props['town'] as String?) ??
              (props['locality'] as String?) ??
              '';
          final district = (props['district'] as String?) ??
              (props['suburb'] as String?) ??
              (props['neighbourhood'] as String?) ??
              '';
          return (city: city, district: district);
        }
      }
      client.close();
    } catch (_) {}
    return (city: '', district: '');
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

  // Camada 2 — LocationIQ (OSM + dados extras, 5.000/dia grátis,
  // cache permanente permitido pelos ToS).
  // Chamada apenas quando Photon retorna vazio.
  Future<List<GeocodingResult>> _searchLocationIQ(
      String query, String key,
      {double userLat = 0.0, double userLon = 0.0}) async {
    final apiKey = AppConstants.locationIqKey;
    if (apiKey.isEmpty) return [];
    final sw = Stopwatch()..start();
    try {
      final cleanQuery = query
          .replaceAll(RegExp(r'\s*,\s*\d+\s*$'), '').trim();
      final params = <String, String>{
        'q':            cleanQuery,
        'key':          apiKey,
        'format':       'json',
        'limit':        '5',
        'countrycodes': 'br',
        'addressdetails': '1',
      };
      // Proximidade — prioriza resultados próximos ao usuário.
      // bounded=0 mantém busca global mas rankeia pelo bias.
      if (userLat != 0.0 && userLon != 0.0) {
        params['lat']     = userLat.toString();
        params['lon']     = userLon.toString();
        params['bounded'] = '0';
      }
      final uri = Uri.https(
          'us1.locationiq.com', '/v1/search', params);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'Sopro/1.0 (Android)');
      final response = await request.close();
      // LocationIQ retorna 404 para "sem resultados" — não é erro HTTP real.
      if (response.statusCode == 404) return [];
      if (response.statusCode != 200) {
        Logger.warn('locationiq_http_error', payload: {
          'query': query, 'status': response.statusCode,
        }, feature: 'geocoding', action: 'locationiq_http',
            durationMs: sw.elapsedMilliseconds);
        return [];
      }
      final body = await response
          .transform(const Utf8Decoder()).join();
      client.close();
      final List<dynamic> features;
      try {
        features = jsonDecode(body) as List<dynamic>;
      } catch (_) {
        return [];
      }
      final results = features
          .whereType<Map<String, dynamic>>()
          .map(_parseLocationIQFeature)
          .whereType<GeocodingResult>()
          .toList();
      Logger.debug('locationiq_result', payload: {
        'query': query,
        'count': results.length,
        'first': results.isNotEmpty
            ? results.first.displayName : 'nenhum',
      }, feature: 'geocoding', action: 'locationiq_parse',
          durationMs: sw.elapsedMilliseconds);
      if (results.isNotEmpty) {
        await _saveToCache(results, key,
            storagePolicy: 'permanent');
      }
      return results;
    } catch (e, st) {
      Logger.error('locationiq_error',
          payload: {'query': query},
          exception: e, stackTrace: st,
          feature: 'geocoding', action: 'locationiq_call',
          durationMs: sw.elapsedMilliseconds);
      return [];
    }
  }

  // Parser do JSON do LocationIQ → GeocodingResult
  GeocodingResult? _parseLocationIQFeature(
      Map<String, dynamic> f) {
    try {
      final lat = double.tryParse(
          f['lat'] as String? ?? '') ?? 0.0;
      final lon = double.tryParse(
          f['lon'] as String? ?? '') ?? 0.0;
      if (lat == 0.0 && lon == 0.0) return null;
      final display =
          f['display_name'] as String? ?? '';
      final addr =
          f['address'] as Map<String, dynamic>? ?? {};
      final name = (addr['amenity'] ??
          addr['shop'] ?? addr['mall'] ??
          addr['pharmacy'] ?? addr['supermarket'] ??
          addr['name'] ?? '') as String;
      final road = (addr['road'] ?? '') as String;
      final city = (addr['city'] ??
          addr['city_district'] ?? addr['town'] ??
          addr['village'] ?? '') as String;
      final state = (addr['state'] ?? '') as String;
      final postcode =
          (addr['postcode'] ?? '') as String;
      final suburb =
          (addr['suburb'] ?? '') as String;
      // Monta displayName limpo
      final parts = <String>[];
      if (name.isNotEmpty) parts.add(name);
      if (road.isNotEmpty) parts.add(road);
      if (city.isNotEmpty) parts.add(city);
      if (state.isNotEmpty) parts.add(state);
      final displayName =
          parts.isNotEmpty ? parts.join(' — ') : display;
      if (displayName.isEmpty) return null;
      return GeocodingResult(
        displayName: displayName,
        lat: lat,
        lon: lon,
        source: 'locationiq',
        hasNumber: road.isNotEmpty,
        name: name,
        address: road,
        district: suburb,
        city: city,
        state: state,
        postalCode: postcode,
      );
    } catch (_) {
      return null;
    }
  }

  // Camada 3 — Google Places (slot reservado, Sprint F3-4).
  // Chamado apenas quando usuário toca "Nenhum desses" após
  // ver resultados do Photon e do LocationIQ.
  // Retorna lista vazia até ser implementado.
  Future<List<GeocodingResult>> searchGooglePlaces(
      String query,
      {double userLat = 0.0, double userLon = 0.0}) async {
    // TODO Sprint F3-4: implementar Google Places Autocomplete
    // + Place Details com session tokens.
    // storagePolicy: '30_days', placeId: place_id do Google.
    Logger.debug('google_places_stub',
        payload: {'query': query},
        feature: 'geocoding', action: 'google_stub');
    return [];
  }

  // Persiste lista de resultados no cache com a chave normalizada
  Future<void> _saveToCache(
      List<GeocodingResult> results, String key,
      {String storagePolicy = 'permanent',
      String placeId = ''}) async {
    final entries = results
        .map((r) => _cacheDao.buildEntry(
              id: _uuid.v4(),
              queryKey: key,
              displayName: r.displayName,
              lat: r.lat,
              lon: r.lon,
              source: r.source,
              storagePolicy: storagePolicy,
              placeId: placeId,
            ))
        .toList();
    await _cacheDao.saveAll(entries);
  }

  // Heurística: o endereço possui número se contiver dígito precedido de vírgula/espaço
  bool _addressHasNumber(String address) =>
      RegExp(r'[,\s]\d+').hasMatch(address);

  // Logradouro líder (com/sem ponto e acento) → só então tratamos como endereço.
  static final _leadStreet = RegExp(
      r'^(rua|r\.|av\.?|avenida|travessa|alameda|estrada|rod(?:ovia|\.)?|pra[cç]a|largo)\b',
      caseSensitive: false);
  // Número da casa no fim ("1000", "1000A"). Não casa CEP (8 dígitos) por acaso —
  // só usamos quando NÃO há palavra "número"/"nº" antes do dígito.
  static final _trailingNumber = RegExp(r'(\d{1,6}[a-zA-Z]?)\s*$');
  // Já contém "número N" / "nº N" / "n. N" → não mexe.
  static final _hasNumberKeyword =
      RegExp(r'(n[uú]mero|n[º°.])\s*\d', caseSensitive: false);

  // Photon resolve endereços BR melhor com "logradouro número N" que com
  // "logradouro N" solto. Quando o texto COMEÇA num logradouro e TERMINA num
  // número puro SEM a palavra "número"/"nº", insere o termo — dá paridade entre
  // "Av Paulista 1000" e "Av Paulista número 1000". Estabelecimentos ("Assaí",
  // "Shopping X") não têm logradouro líder → ficam intactos.
  static String _insertHouseNumberKeyword(String raw) {
    final q = raw.trim();
    if (!_leadStreet.hasMatch(q)) return q;      // não é logradouro
    if (_hasNumberKeyword.hasMatch(q)) return q; // já tem "número N"
    final m = _trailingNumber.firstMatch(q);
    if (m == null) return q;                     // sem número no fim
    final head = q.substring(0, m.start).replaceAll(RegExp(r'[,\s]+$'), '');
    if (head.isEmpty) return q;                  // era só um número
    return '$head número ${m.group(1)}';
  }
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
