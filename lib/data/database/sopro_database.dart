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
// Versão atual: 1
// Histórico de migrações fica em _migration abaixo.
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // onCreate é chamado apenas na primeira vez que o banco é criado
        onCreate: (m) async {
          await m.createAll();
        },
        // onUpgrade é chamado quando schemaVersion aumenta
        onUpgrade: (m, from, to) async {
          // Sprint 1: versão inicial, sem migrações necessárias ainda.
          // Quando chegar Sprint N com nova coluna/tabela, adicionar aqui:
          // if (from < 2) { await m.addColumn(...); }
        },
      );
}

// Abre a conexão com o banco usando drift_flutter (sqlite3_flutter_libs).
// O nome do arquivo é "sopro.db" no diretório de dados do app.
QueryExecutor _openConnection() {
  return driftDatabase(name: 'sopro');
}
