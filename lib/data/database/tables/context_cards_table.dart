import 'package:drift/drift.dart';

// Definição da tabela "context_cards" no SQLite via Drift.
// Armazena o perfil público do usuário trocado via BLE.
// Por design, espera-se apenas um cartão ativo por vez (o próprio usuário),
// mas a tabela suporta múltiplos para histórico de versões.
class ContextCards extends Table {
  // UUID v4 como chave primária
  TextColumn get id => text()();

  // Nome de exibição escolhido pelo usuário
  TextColumn get displayName => text().withLength(min: 1, max: 50)();

  // Bio / descrição livre
  TextColumn get bio => text().withLength(max: 500)();

  // Tags separadas por vírgula — parsing feito na camada de domínio
  TextColumn get tags => text().withDefault(const Constant(''))();

  // Timestamp de criação
  DateTimeColumn get createdAt => dateTime()();

  // Timestamp da última edição — enviado via BLE para comparar versões
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
