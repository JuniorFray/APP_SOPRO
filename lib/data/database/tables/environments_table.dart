import 'package:drift/drift.dart';

// Definição da tabela "environments" no SQLite via Drift.
// Cada linha representa um local físico monitorado pelo geofence.
class Environments extends Table {
  // UUID v4 como chave primária (texto, não inteiro auto-increment)
  TextColumn get id => text()();

  // Nome legível pelo usuário
  TextColumn get name => text().withLength(min: 1, max: 100)();

  // Latitude do centro do geofence
  RealColumn get latitude => real()();

  // Longitude do centro do geofence
  RealColumn get longitude => real()();

  // Raio em metros; valor mínimo definido na camada de domínio
  RealColumn get radiusMeters => real()();

  // Timestamp de criação armazenado como milissegundos desde epoch
  DateTimeColumn get createdAt => dateTime()();

  // Marca este ambiente como "Mercado" — troca o sistema de gatilhos de texto
  // por uma lista de compras gerenciável. Default false (ambiente comum).
  BoolColumn get isMarket => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
