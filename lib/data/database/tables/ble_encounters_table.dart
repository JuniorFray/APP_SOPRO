import 'package:drift/drift.dart';

// Tabela que persiste encontros BLE com outros usuários Sopro.
//
// Estratégia: um registro por dispositivo (deviceId = PK).
// Tocar a mesma pessoa duas vezes faz upsert — atualiza o cartão e o timestamp.
// Isso evita acumulação de linhas duplicadas e mantém o histórico compacto.
//
// Adicionada em schemaVersion 3 — Sprint 9.
class BleEncounters extends Table {
  // Endereço MAC do dispositivo BLE — chave primária única por aparelho
  TextColumn get deviceId => text()();

  // Campos do ContextCard recebido via GATT
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get role        => text().withDefault(const Constant(''))();
  TextColumn get company     => text().withDefault(const Constant(''))();
  TextColumn get bio         => text().withDefault(const Constant(''))();
  TextColumn get tags        => text().withDefault(const Constant(''))();

  // Data/hora do último encontro registrado com este dispositivo
  DateTimeColumn get encounteredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {deviceId};
}
