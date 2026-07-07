import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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

  // Bounding box aproximada do Brasil para o Photon (reduz resultados irrelevantes)
  static const _photonBbox = 'bbox=-73.9,-33.7,-34.7,5.3';

  final GeocodingCacheDao _cacheDao;

  AndroidGeocodingService(this._cacheDao);

  // ── Forward geocoding ─────────────────────────────────────────────────────

  @override
  Future<List<GeocodingResult>> search(String query) async {
    final key = _normalizeKey(query);

    // Camada 1: cache local
    final cached = await _cacheDao.findByKey(key);
    if (cached.isNotEmpty) {
      return cached
          .map((row) => GeocodingResult(
                displayName: row.displayName,
                lat: row.lat,
                lon: row.lon,
                source: row.source,
                hasNumber: _addressHasNumber(row.displayName),
              ))
          .toList();
    }

    // Camada 2: Geocoder nativo Android com bounding box do usuário
    try {
      final prefs  = await SharedPreferences.getInstance();
      final userLat = prefs.getDouble('last_known_lat') ?? 0.0;
      final userLon = prefs.getDouble('last_known_lon') ?? 0.0;

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
        if (results.isNotEmpty) {
          await _saveToCache(results, key);
          return results;
        }
      }
    } catch (_) {
      // Geocoder indisponível (emulador sem Google Play) — cai para Photon
    }

    // Camada 3: Photon fallback
    return _searchPhoton(query, key);
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
    } catch (_) {}

    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
  Future<List<GeocodingResult>> _searchPhoton(String query, String key) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final uri = Uri.parse(
          'https://photon.komoot.io/api/?q=$encodedQuery&limit=5&$_photonBbox');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();

      if (response.statusCode != 200) return [];

      final body = await response.transform(const Utf8Decoder()).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? [];

      final results = features
          .map((f) => _parsePhotonFeature(f as Map<String, dynamic>))
          .whereType<GeocodingResult>()
          .toList();

      if (results.isNotEmpty) {
        await _saveToCache(results, key);
      }

      return results;
    } catch (_) {
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
    } catch (_) {
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
