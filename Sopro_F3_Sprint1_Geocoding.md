# Sopro F3 — Sprint 1: Geocoding com Cache
> Geocoder nativo Android como fonte principal — validado por benchmark de 466 endereços

---

## Decisão técnica (baseada em benchmark real)

Benchmark executado em 06/07/2026 — 466 endereços, cobertura nacional:

| Métrica | Resultado |
|---|---|
| Taxa de sucesso | 100% (466/466) |
| Tempo médio | 184ms |
| Precisão com número (categoria real) | 86.6% |
| Estabelecimentos por nome | 59.1% |
| Cidade errada | 4.7% (casos ambíguos) |

**Veredicto:** Geocoder nativo do Android é a fonte primária. Gratuito, sem API key, sem cota, usa motor Google Maps em background. A tela de confirmação do Sprint F3-2 mitiga os 4.7% de cidade errada.

---

## Arquitetura de geocoding em camadas

```
Usuário digita/fala endereço ou nome de local
          ↓
CAMADA 1: Cache local (SQLite — tabela geocoding_cache)
  → HIT: retornar imediatamente (zero custo, zero latência)
  → MISS: continuar

CAMADA 2: Geocoder nativo Android
  via MethodChannel "com.sopro.sopro/geocoder"
  → Encontrou resultado confiável: salvar no cache + retornar lista
  → Resultado vazio ou impreciso: continuar

CAMADA 3: Photon (OSM) — fallback HTTP
  GET https://photon.komoot.io/api/?q=QUERY&limit=5&bbox=-73.9,-33.7,-34.7,5.3
  → Salvar no cache + retornar
  → Gratuito, sem API key, sem restrição de cache

CAMADA FUTURA (plug-in, não implementada agora):
  Slot reservado para HERE, Google Places ou outro provedor pago
  Ativável via feature flag sem alterar o restante da arquitetura
```

---

## Modelo de dados — tabela geocoding_cache (Drift v5)

```dart
// lib/data/database/tables/geocoding_cache_table.dart
//
// Cache de resultados de geocoding para evitar chamadas repetidas.
// TTL padrão: 30 dias.
// Chave: query normalizada (lowercase, sem acentos) para forward geocoding
//        ou "rev:{lat_arredondado}:{lon_arredondado}" para reverso.

class GeocodingCache extends Table {
  TextColumn get id => text()();
  TextColumn get queryKey => text()();       // chave normalizada de busca
  TextColumn get displayName => text()();    // nome exibível (ex: "Av. Paulista, 1578")
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  TextColumn get source => text()();         // 'geocoder_native' | 'photon'
  IntColumn get expiresAt => integer()();    // timestamp Unix em ms
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## Interface abstrata (iOS-ready)

```dart
// lib/infrastructure/geocoding/geocoding_platform_interface.dart
//
// Contrato que permite trocar implementação por plataforma.
// Android: Geocoder nativo via MethodChannel.
// iOS futuro: MKLocalSearch via MethodChannel Swift.

abstract class GeocodingPlatformInterface {
  Future<List<GeocodingResult>> search(String query);
  Future<GeocodingResult?> reverse(double lat, double lon);
}

class GeocodingResult {
  final String displayName;
  final double lat;
  final double lon;
  final String source;      // origem do resultado
  final bool hasNumber;     // se o resultado inclui número de rua
  GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.source,
    this.hasNumber = false,
  });
}
```

---

## Implementação Android (GeocodingService)

```dart
// lib/infrastructure/geocoding/android_geocoding_service.dart
//
// Implementa busca em cascata: cache → Geocoder nativo → Photon fallback.

class AndroidGeocodingService implements GeocodingPlatformInterface {
  static const _channel = MethodChannel('com.sopro.sopro/geocoder');
  // Cache DAO injetado via Riverpod
  final GeocodingCacheDao _cacheDao;

  @override
  Future<List<GeocodingResult>> search(String query) async {
    final key = _normalizeKey(query);

    // 1. Cache local
    final cached = await _cacheDao.findByKey(key);
    if (cached.isNotEmpty) return cached;

    // 2. Geocoder nativo Android
    try {
      final raw = await _channel.invokeMethod('searchAddress', {'query': query});
      final results = _parseNativeResults(raw, query);
      if (results.isNotEmpty) {
        await _cacheDao.saveAll(results, key);
        return results;
      }
    } catch (_) {}

    // 3. Photon fallback
    return _searchPhoton(query, key);
  }

  // Normaliza a chave: lowercase + remove acentos + trim
  String _normalizeKey(String query) =>
      query.toLowerCase().trim()
          .replaceAll(RegExp(r'[áàãâä]'), 'a')
          .replaceAll(RegExp(r'[éèêë]'), 'e')
          .replaceAll(RegExp(r'[íìîï]'), 'i')
          .replaceAll(RegExp(r'[óòõôö]'), 'o')
          .replaceAll(RegExp(r'[úùûü]'), 'u')
          .replaceAll(RegExp(r'[ç]'), 'c');
}
```

---

## Kotlin: MethodChannel geocoder (já implementado no benchmark)

O MethodChannel `com.sopro.sopro/geocoder` com o método `searchAddress`
foi implementado e validado durante o benchmark. Reusar exatamente esse código.
Adicionar método `reverseGeocode` para geocoding reverso (lat/lon → nome):

```kotlin
"reverseGeocode" -> {
    val lat = call.argument<Double>("lat") ?: 0.0
    val lon = call.argument<Double>("lon") ?: 0.0
    try {
        @Suppress("DEPRECATION")
        val geocoder = android.location.Geocoder(this, java.util.Locale("pt", "BR"))
        val addresses = geocoder.getFromLocation(lat, lon, 1)
        if (!addresses.isNullOrEmpty()) {
            val addr = addresses[0]
            result.success(mapOf(
                "found" to true,
                "display_name" to (addr.featureName
                    ?: addr.thoroughfare
                    ?: addr.subLocality
                    ?: addr.locality
                    ?: "Local desconhecido"),
                "returned_address" to (addr.getAddressLine(0) ?: ""),
                "lat" to lat,
                "lon" to lon
            ))
        } else {
            result.success(mapOf("found" to false))
        }
    } catch (e: Exception) {
        result.success(mapOf("found" to false))
    }
}
```

---

## Stub iOS (implementação futura)

```dart
// lib/infrastructure/geocoding/ios_geocoding_service_stub.dart
//
// Stub para iOS. Implementar com MKLocalSearch via MethodChannel Swift
// quando o suporte iOS for desenvolvido (Fase 4).

class IOSGeocodingService implements GeocodingPlatformInterface {
  @override
  Future<List<GeocodingResult>> search(String query) async {
    // TODO iOS: usar MKLocalSearch via MethodChannel
    // MKLocalSearchRequest + MKLocalSearch.start()
    throw UnsupportedError('Geocoding iOS não implementado ainda');
  }

  @override
  Future<GeocodingResult?> reverse(double lat, double lon) async {
    // TODO iOS: usar CLGeocoder.reverseGeocodeLocation()
    throw UnsupportedError('Reverse geocoding iOS não implementado ainda');
  }
}
```

---

## Slot para provedor futuro

```dart
// lib/infrastructure/geocoding/premium_geocoding_service_stub.dart
//
// Slot reservado para provedor premium (HERE, Google Places, etc).
// Ativar via feature flag quando necessário.
// Não implementado — zero custo até ser necessário.

class PremiumGeocodingService implements GeocodingPlatformInterface {
  final String apiKey;
  PremiumGeocodingService({required this.apiKey});

  @override
  Future<List<GeocodingResult>> search(String query) async {
    // TODO: implementar HERE ou Google Places quando escala exigir
    // endpoint: https://geocode.search.hereapi.com/v1/geocode
    // ou: https://places.googleapis.com/v1/places:autocomplete
    throw UnimplementedError('Provedor premium não configurado');
  }

  @override
  Future<GeocodingResult?> reverse(double lat, double lon) async {
    throw UnimplementedError('Provedor premium não configurado');
  }
}
```

---

## Tarefas do Sprint F3-1

- [ ] Criar `geocoding_cache_table.dart` + DAO + migration Drift v5
- [ ] Criar `geocoding_platform_interface.dart` e `GeocodingResult`
- [ ] Criar `android_geocoding_service.dart` (cache + Geocoder + Photon)
- [ ] Criar `ios_geocoding_service_stub.dart`
- [ ] Criar `premium_geocoding_service_stub.dart`
- [ ] Adicionar método `reverseGeocode` ao MethodChannel Kotlin existente
- [ ] Criar `GeocodingRepository` com provider Riverpod
- [ ] Remover tela de benchmark do menu (manter código inerte)
- [ ] flutter build apk --debug sem erros

---

## Referências

- Benchmark executado: 466 endereços, 06/07/2026, Motorola G52 Android 13
- Dados exportados para tabela `geocoder_benchmark` no Supabase
- Relatório visual disponível no histórico do chat

---

*Sprint F3-1 — atualizado 06/07/2026*
