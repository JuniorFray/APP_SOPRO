import 'package:drift/drift.dart';

// Cache de resultados de geocoding para evitar chamadas repetidas a serviços externos.
//
// Validade por storagePolicy: 'permanent' (Photon/LocationIQ, nunca expira) ou
// '30_days' (Google Places, renovar via placeId). Regra aplicada no DAO.findByKey.
// Chave de lookup:
//   - Forward geocoding : query normalizada (lowercase, sem acentos)
//   - Reverse geocoding : "rev:{lat_5decimais}:{lon_5decimais}"
//
// Adicionada em schemaVersion 5 — Sprint F3-1.
// storagePolicy + placeId adicionados em schemaVersion 6 — Sprint F3-3.
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

  // Fonte do resultado: 'geocoder_native' | 'photon' | 'locationiq'
  TextColumn get source => text()();

  // Política de armazenamento:
  //   'permanent'  — Photon e LocationIQ (sem expiração)
  //   '30_days'    — Google Places (renovar via placeId após 30 dias)
  TextColumn get storagePolicy => text().withDefault(const Constant('permanent'))();

  // ID externo do provider (Google place_id). Vazio para Photon/LocationIQ.
  // Armazenável indefinidamente — usado para renovar coords Google após 30 dias.
  TextColumn get placeId => text().withDefault(const Constant(''))();

  // Timestamp Unix em ms de criação da entrada
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
