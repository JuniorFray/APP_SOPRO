import 'package:drift/drift.dart';

// Cache de resultados de geocoding para evitar chamadas repetidas a serviços externos.
//
// TTL padrão: 30 dias (calculado em ms na camada de serviço).
// Chave de lookup:
//   - Forward geocoding : query normalizada (lowercase, sem acentos)
//   - Reverse geocoding : "rev:{lat_5decimais}:{lon_5decimais}"
//
// Adicionada em schemaVersion 5 — Sprint F3-1.
class GeocodingCache extends Table {
  // UUID gerado na camada de serviço — garante unicidade mesmo em upserts concorrentes
  TextColumn get id => text()();

  // Chave de busca normalizada usada para HIT/MISS no cache
  TextColumn get queryKey => text()();

  // Nome exibível do local (ex: "Av. Paulista, 1578 — São Paulo, SP")
  TextColumn get displayName => text()();

  // Coordenadas retornadas pelo geocoder
  RealColumn get lat => real()();
  RealColumn get lon => real()();

  // Fonte do resultado: 'geocoder_native' | 'photon'
  TextColumn get source => text()();

  // Timestamp Unix em ms após o qual a entrada deve ser ignorada (TTL = 30 dias)
  IntColumn get expiresAt => integer()();

  // Timestamp Unix em ms de criação da entrada
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
