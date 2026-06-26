import 'package:drift/drift.dart';

import 'environments_table.dart';

// Definição da tabela "triggers" no SQLite via Drift.
// Cada linha é um gatilho (lembrete/intenção) vinculado a um Environment.
//
// @DataClassName renomeia o data class gerado de "Trigger" para "TriggerRow"
// evitando conflito com a classe Trigger interna do próprio pacote Drift.
@DataClassName('TriggerRow')
class Triggers extends Table {
  // UUID v4 como chave primária
  TextColumn get id => text()();

  // FK para a tabela environments; cascade delete remove triggers órfãos
  TextColumn get environmentId =>
      text().references(Environments, #id, onDelete: KeyAction.cascade)();

  // Título curto exibido na notificação
  TextColumn get title => text().withLength(min: 1, max: 200)();

  // Conteúdo completo do gatilho
  TextColumn get content => text()();

  // Flag de ativação; 1 = ativo, 0 = pausado
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  // Timestamp de criação
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
