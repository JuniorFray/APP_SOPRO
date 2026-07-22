import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/weather_cache_table.dart';
import '../tables/weather_forecast_cache_table.dart';

// DAO para os caches de clima: atual (WeatherCacheEntries) e previsão
// (WeatherForecastCache). HIT/MISS por chave de coordenada arredondada,
// respeitando o TTL (expiresAt).
//
// O data class gerado se chama WeatherCacheEntry; o Companion,
// WeatherCacheEntriesCompanion (derivado do nome da tabela).
part 'weather_cache_dao.g.dart';

@DriftAccessor(tables: [WeatherCacheEntries, WeatherForecastCache])
class WeatherCacheDao extends DatabaseAccessor<SoproDatabase>
    with _$WeatherCacheDaoMixin {
  WeatherCacheDao(super.db);

  // Retorna a entrada da chave se existir E ainda não expirou (expiresAt > now),
  // senão null. Entradas expiradas são ignoradas (nova chamada HTTP no serviço).
  Future<WeatherCacheEntry?> findValid(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (select(weatherCacheEntries)
          ..where((t) => t.id.equals(key))
          ..where((t) => t.expiresAt.isBiggerThanValue(now)))
        .getSingleOrNull();
  }

  // Insere ou atualiza a entrada de uma chave (upsert idempotente).
  Future<void> upsert(WeatherCacheEntriesCompanion entry) =>
      into(weatherCacheEntries).insertOnConflictUpdate(entry);

  // Previsão em cache válida (não expirada) ou null.
  Future<WeatherForecastCacheData?> findValidForecast(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (select(weatherForecastCache)
          ..where((t) => t.id.equals(key))
          ..where((t) => t.expiresAt.isBiggerThanValue(now)))
        .getSingleOrNull();
  }

  // Upsert da previsão (JSON já processado) de uma chave.
  Future<void> upsertForecast(WeatherForecastCacheCompanion entry) =>
      into(weatherForecastCache).insertOnConflictUpdate(entry);
}
