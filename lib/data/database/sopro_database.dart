import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/context_cards_dao.dart';
import 'daos/environments_dao.dart';
import 'daos/triggers_dao.dart';
import 'tables/context_cards_table.dart';
import 'tables/environments_table.dart';
import 'tables/triggers_table.dart';

// Arquivo gerado automaticamente pelo build_runner — não editar manualmente.
// Execute: dart run build_runner build --delete-conflicting-outputs
part 'sopro_database.g.dart';

// Banco de dados principal do Sopro.
//
// Usa drift_flutter que por padrão cria um arquivo SQLite no diretório de
// dados do app (getApplicationDocumentsDirectory). Em produção será substituído
// por SQLCipher para criptografia em repouso (privacidade antes de feature).
//
// Histórico de versões:
//   v1 (Sprint 1): criação das tabelas Environments, Triggers, ContextCards
//   v2 (Sprint 8): adição de role + company na tabela ContextCards
@DriftDatabase(
  tables: [
    Environments,
    Triggers,
    ContextCards,
  ],
  daos: [
    EnvironmentsDao,
    TriggersDao,
    ContextCardsDao,
  ],
)
class SoproDatabase extends _$SoproDatabase {
  SoproDatabase() : super(_openConnection());

  // Construtor alternativo para testes — recebe a conexão de fora (in-memory)
  SoproDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // onCreate: chamado apenas na primeira criação do banco (instalação limpa)
        onCreate: (m) async {
          await m.createAll();
        },
        // onUpgrade: chamado quando schemaVersion aumenta em instalações existentes
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Sprint 8: novos campos de cargo e empresa no perfil BLE
            await m.addColumn(contextCards, contextCards.role);
            await m.addColumn(contextCards, contextCards.company);
          }
        },
      );
}

// Abre a conexão com o banco usando drift_flutter (sqlite3_flutter_libs).
// O nome do arquivo é "sopro.db" no diretório de dados do app.
QueryExecutor _openConnection() {
  return driftDatabase(name: 'sopro');
}
