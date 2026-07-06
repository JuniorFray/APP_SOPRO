import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/geocoding_cache_table.dart';

// DAO para a tabela de cache de geocoding.
// Gerencia HIT/MISS por queryKey e aplica TTL de 30 dias automaticamente.
part 'geocoding_cache_dao.g.dart';

// TTL padrão: 30 dias em milissegundos
const _kTtlMs = 30 * 24 * 60 * 60 * 1000;

@DriftAccessor(tables: [GeocodingCache])
class GeocodingCacheDao extends DatabaseAccessor<SoproDatabase>
    with _$GeocodingCacheDaoMixin {
  GeocodingCacheDao(super.db);

  // Busca entradas válidas (não expiradas) para uma chave normalizada.
  // Retorna lista vazia em MISS ou quando o TTL expirou.
  Future<List<GeocodingCacheData>> findByKey(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (select(geocodingCache)
          ..where((row) => row.queryKey.equals(key) & row.expiresAt.isBiggerThanValue(now)))
        .get();
  }

  // Persiste uma lista de resultados vinculados à mesma chave de busca.
  // Usa insertOnConflictUpdate para idempotência (mesma chave sobrescreve).
  Future<void> saveAll(List<GeocodingCacheCompanion> entries) async {
    await batch((b) => b.insertAllOnConflictUpdate(geocodingCache, entries));
  }

  // Remove entradas cuja data de expiração já passou.
  // Deve ser chamado periodicamente para manter o banco compacto.
  Future<int> deleteExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (delete(geocodingCache)
          ..where((row) => row.expiresAt.isSmallerOrEqualValue(now)))
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
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return GeocodingCacheCompanion(
      id:          Value(id),
      queryKey:    Value(queryKey),
      displayName: Value(displayName),
      lat:         Value(lat),
      lon:         Value(lon),
      source:      Value(source),
      expiresAt:   Value(now + _kTtlMs),
      createdAt:   Value(now),
    );
  }
}
