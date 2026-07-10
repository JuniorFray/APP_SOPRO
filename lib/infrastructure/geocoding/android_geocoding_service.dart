import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/core/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/daos/geocoding_cache_dao.dart';
import 'geocoding_platform_interface.dart';

// Busca em cascata para Android:
//   CAMADA 1 — Cache local SQLite (zero custo, zero latência)
//   CAMADA 2 — Geocoder nativo Android via MethodChannel (grátis, sem cota)
//   CAMADA 3 — Photon/OSM via HTTP (grátis, sem API key)
//
// Cada resultado bem-sucedido é salvo no cache antes de ser retornado,
// garantindo que chamadas futuras com a mesma query sejam servidas localmente.
class AndroidGeocodingService implements GeocodingPlatformInterface {
  static const _channel = MethodChannel('com.sopro.sopro/geocoder');
  static const _uuid = Uuid();

  final GeocodingCacheDao _cacheDao;

  AndroidGeocodingService(this._cacheDao);

  // ── Forward geocoding ─────────────────────────────────────────────────────

  @override
  Future<List<GeocodingResult>> search(String query) async {
    final key = _normalizeKey(query);

    // Camada 1: cache local (apenas resultados com qualidade suficiente)
    final cached = await _cacheDao.findByKey(key);
    final qualityCached = cached.where((row) =>
        _isQualityResult(GeocodingResult(
          displayName: row.displayName,
          lat: row.lat,
          lon: row.lon,
          source: row.source,
        ))).toList();
    if (qualityCached.isNotEmpty) {
      return qualityCached
          .map((row) => GeocodingResult(
                displayName: row.displayName,
                lat: row.lat,
                lon: row.lon,
                source: row.source,
                hasNumber: _addressHasNumber(row.displayName),
              ))
          .toList();
    }

    // Lê localização do usuário antes do try — necessário no fallback Photon também
    final prefs   = await SharedPreferences.getInstance();
    final userLat = await _readCoord(prefs, 'last_known_lat');
    final userLon = await _readCoord(prefs, 'last_known_lon');
    // Estabelecimentos (sem palavra de rua ou número) vão direto ao Photon
    if (_looksLikeEstablishment(query)) {
      return _searchPhoton(query, key, userLat: userLat, userLon: userLon);
    }

    // Camada 2: Geocoder nativo Android com bounding box do usuário
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

    // Camada 3: Photon fallback
    return _searchPhoton(query, key, userLat: userLat, userLon: userLon);
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

  // Queries sem palavra de rua e sem número são tratadas como estabelecimento —
  // o Photon (OSM) é mais preciso que o Geocoder nativo para esses casos
  bool _looksLikeEstablishment(String query) {
    final q = query.toLowerCase();
    const streetWords = ['rua', 'av.', 'avenida', 'travessa',
                         'alameda', 'estrada', 'rodovia', 'praca'];
    final hasStreetWord = streetWords.any((w) => q.contains(w));
    final hasNumber     = RegExp(r'\d+').hasMatch(q);
    return !hasStreetWord && !hasNumber;
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

  // Normaliza a chave de cache: lowercase + remove acentos + trim
  String _normalizeKey(String query) => query
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[áàãâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòõôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');

  // Monta o displayName preferindo o endereço completo; fallback para partes disponíveis
  String _buildDisplayName(
      String address, String name, String city, String state) {
    if (address.isNotEmpty) return address;
    return [name, city, state].where((s) => s.isNotEmpty).join(', ');
  }

  // Chama a API Photon (OSM) com bounding box do Brasil
  Future<List<GeocodingResult>> _searchPhoton(String query, String key,
      {double userLat = 0.0, double userLon = 0.0}) async {
    Logger.debug('photon_called', payload: {'query': query},
        feature: 'geocoding', action: 'photon_start');
    final sw = Stopwatch()..start();
    try {
      // Remove sufixos numéricos do debounce (ex: ", 52") e monta URL com encoding correto
      final cleanQuery = query.replaceAll(RegExp(r'\s*,\s*\d+\s*$'), '').trim();
      final params = <String, String>{
        'q':     cleanQuery,
        'limit': '5',
        'bbox':  '-73.9,-33.7,-34.7,5.3',
      };
      if (userLat != 0.0 && userLon != 0.0) {
        params['lat'] = userLat.toString();
        params['lon'] = userLon.toString();
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
      final state   = props['state']   as String? ?? '';

      // Monta nome exibível priorizando rua + número
      final parts = <String>[];
      if (street.isNotEmpty) {
        parts.add(housen.isNotEmpty ? '$street, $housen' : street);
      } else if (name.isNotEmpty) {
        parts.add(name);
      }
      if (city.isNotEmpty) parts.add(city);
      if (state.isNotEmpty) parts.add(state);

      final displayName = parts.isNotEmpty ? parts.join(' — ') : name;
      if (displayName.isEmpty) return null;

      return GeocodingResult(
        displayName: displayName,
        lat: lat,
        lon: lon,
        source: 'photon',
        hasNumber: housen.isNotEmpty,
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
