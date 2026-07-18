import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/geocoding_cache_table.dart';

// DAO para a tabela de cache de geocoding.
// Gerencia HIT/MISS por queryKey e aplica a storagePolicy (permanent/30_days).
part 'geocoding_cache_dao.g.dart';

@DriftAccessor(tables: [GeocodingCache])
class GeocodingCacheDao extends DatabaseAccessor<SoproDatabase>
    with _$GeocodingCacheDaoMixin {
  GeocodingCacheDao(super.db);

  // Busca entradas válidas para uma chave normalizada, respeitando storagePolicy:
  //   permanent → sempre válido
  //   30_days   → válido se createdAt + 30 dias > agora
  Future<List<GeocodingCacheData>> findByKey(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    return (select(geocodingCache)
          ..where((t) => t.queryKey.equals(key))
          ..where((t) =>
              t.storagePolicy.equals('permanent') |
              t.createdAt.isBiggerThanValue(now - thirtyDaysMs)))
        .get();
  }

  // Persiste uma lista de resultados vinculados à mesma chave de busca.
  // Usa insertOnConflictUpdate para idempotência (mesma chave sobrescreve).
  Future<void> saveAll(List<GeocodingCacheCompanion> entries) async {
    await batch((b) => b.insertAllOnConflictUpdate(geocodingCache, entries));
  }

  // Remove entradas '30_days' cujo createdAt + 30 dias já passou. Entradas
  // 'permanent' nunca são removidas. Mantém o banco compacto.
  Future<int> deleteExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    return (delete(geocodingCache)
          ..where((t) =>
              t.storagePolicy.equals('30_days') &
              t.createdAt.isSmallerOrEqualValue(now - thirtyDaysMs)))
        .go();
  }

  // Remove todas as entradas — útil em reset de dados.
  Future<int> deleteAll() => delete(geocodingCache).go();

  // Gera um GeocodingCacheCompanion pronto para insert dado um resultado bruto.
  // [id] deve ser um UUID gerado pelo chamador.
  GeocodingCacheCompanion buildEntry({
    required String id,
    required String queryKey,
    required String displayName,
    required double lat,
    required double lon,
    required String source,
    String storagePolicy = 'permanent',
    String placeId = '',
  }) => GeocodingCacheCompanion.insert(
        id:            id,
        queryKey:      queryKey,
        displayName:   displayName,
        lat:           lat,
        lon:           lon,
        source:        source,
        storagePolicy: Value(storagePolicy),
        placeId:       Value(placeId),
        createdAt:     DateTime.now().millisecondsSinceEpoch,
      );
}
