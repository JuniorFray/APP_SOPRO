import 'package:drift/drift.dart';

// Definição da tabela "context_cards" no SQLite via Drift.
// Armazena o perfil público do usuário trocado via BLE.
//
// schemaVersion 1: id, displayName, bio, tags, createdAt, updatedAt
// schemaVersion 2: + role (cargo), + company (empresa) — Sprint 8
// schemaVersion 4: + phone (WhatsApp/telefone) — Sprint 13
class ContextCards extends Table {
  // UUID v4 como chave primária
  TextColumn get id => text()();

  // Nome de exibição escolhido pelo usuário (1-50 caracteres)
  TextColumn get displayName => text().withLength(min: 1, max: 50)();

  // Cargo profissional (ex: "Desenvolvedor Flutter", "Designer")
  TextColumn get role => text().withDefault(const Constant(''))();

  // Empresa ou organização (ex: "Google", "USP", "Freelancer")
  TextColumn get company => text().withDefault(const Constant(''))();

  // Bio / nota pessoal — texto livre sobre o usuário ou sua intenção atual
  TextColumn get bio => text().withLength(max: 500)();

  // Tags de interesse separadas por vírgula (ex: "tech,música,café")
  TextColumn get tags => text().withDefault(const Constant(''))();

  // Número de WhatsApp/telefone (só dígitos, ex: "11999998888") — opcional
  TextColumn get phone => text().withDefault(const Constant(''))();

  // Timestamp de criação do cartão
  DateTimeColumn get createdAt => dateTime()();

  // Timestamp da última edição — enviado via BLE para comparar versões
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
