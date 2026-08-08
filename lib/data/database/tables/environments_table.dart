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

  // Caminho local (diretório de documentos do app) da foto usada na plaquinha 3D
  // deste ambiente. Nullable: sem foto → usa a arte Sopro padrão. Foto por
  // ambiente (não global). Nunca sai do dispositivo (não migra pro Supabase).
  TextColumn get pinImagePath => text().nullable()();

  // Sync (Estágio 2.1) — última modificação local (LWW) e tombstone de exclusão.
  // Nullable: linhas antigas ficam null até a migração/próxima escrita preencher.
  // deletedAt != null = soft delete (linha some da UI, sobe como tombstone).
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  // Sync (Fase 3 — compartilhamento) — dono da linha quando ela é uma CÓPIA
  // read-only de um ambiente compartilhado por OUTRO usuário. null = linha própria
  // (meu dado ou legado). Preenchido no PULL com o user_id remoto quando != eu.
  // O PUSH nunca reenvia linhas com ownerId != null (o convidado não é dono delas).
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
