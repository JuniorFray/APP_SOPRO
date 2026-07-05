import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daos/ble_encounters_dao.dart';
import 'daos/context_cards_dao.dart';
import 'daos/environments_dao.dart';
import 'daos/triggers_dao.dart';
import 'tables/ble_encounters_table.dart';
import 'tables/context_cards_table.dart';
import 'tables/environments_table.dart';
import 'tables/triggers_table.dart';

// Arquivo gerado automaticamente pelo build_runner — não editar manualmente.
// Execute: dart run build_runner build --delete-conflicting-outputs
part 'sopro_database.g.dart';

// Banco de dados principal do Sopro.
//
// Armazenamento: drift_flutter usa getApplicationDocumentsDirectory() —
//   Android: /data/data/com.sopro.sopro/app_flutter/sopro.db  (armazenamento
//            privado do app, apagado na desinstalação pelo Android).
//   Nota: Android Auto Backup (API 23+) pode restaurar SharedPreferences sem
//         restaurar o banco. Por isso AppInitializer detecta esta inconsistência
//         e reseta o flag 'onboarding_done' quando prefs dizem "done" mas banco
//         está vazio — veja app_initializer.dart, seção "Detecção de prefs obsoletas".
//
// Em produção será substituído por SQLCipher para criptografia em repouso
// (privacidade antes de feature).
//
// Histórico de versões:
//   v1 (Sprint 1): criação das tabelas Environments, Triggers, ContextCards
//   v2 (Sprint 8): adição de role + company na tabela ContextCards
//   v3 (Sprint 9): nova tabela BleEncounters — histórico de encontros BLE
//   v4 (Sprint 13): adição de phone em ContextCards e BleEncounters
@DriftDatabase(
  tables: [
    Environments,
    Triggers,
    ContextCards,
    BleEncounters,
  ],
  daos: [
    EnvironmentsDao,
    TriggersDao,
    ContextCardsDao,
    BleEncountersDao,
  ],
)
class SoproDatabase extends _$SoproDatabase {
  SoproDatabase() : super(_openConnection());

  // Construtor alternativo para testes — recebe a conexão de fora (in-memory)
  SoproDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // onCreate: chamado apenas na primeira criação do banco (instalação limpa)
        onCreate: (m) async {
          await m.createAll();
        },
        // onUpgrade: chamado quando schemaVersion aumenta em instalações existentes
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Sprint 8: campos de cargo e empresa no perfil BLE
            await m.addColumn(contextCards, contextCards.role);
            await m.addColumn(contextCards, contextCards.company);
          }
          if (from < 3) {
            // Sprint 9: tabela de histórico de encontros BLE
            await m.createTable(bleEncounters);
          }
          if (from < 4) {
            // Sprint 13: campo phone/WhatsApp no ContextCard e BleEncounters
            await m.addColumn(contextCards, contextCards.phone);
            await m.addColumn(bleEncounters, bleEncounters.phone);
          }
        },
      );
}

// Abre a conexão com o banco usando LazyDatabase com caminho explícito.
// Persiste o caminho em SharedPreferences para uso pelo FloatingVoiceService.
QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'sopro.db'));
    // Salvar o caminho exato para o FloatingVoiceService usar
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flutter.sopro_db_path', file.absolute.path);
    return NativeDatabase(file);
  });
}
