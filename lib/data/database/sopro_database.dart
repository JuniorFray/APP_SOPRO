import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daos/ble_encounters_dao.dart';
import 'daos/context_cards_dao.dart';
import 'daos/environments_dao.dart';
import 'daos/geocoding_cache_dao.dart';
import 'daos/triggers_dao.dart';
import 'tables/ble_encounters_table.dart';
import 'tables/context_cards_table.dart';
import 'tables/environments_table.dart';
import 'tables/geocoding_cache_table.dart';
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
//   v5 (Sprint F3-1): nova tabela GeocodingCache — cache de resultados de geocoding
//   v6 (Sprint F3-3): GeocodingCache ganha storagePolicy + placeId; remove expiresAt
//   v7: title de Triggers deixa de ter comprimento mínimo (permite gatilho sem título)
@DriftDatabase(
  tables: [
    Environments,
    Triggers,
    ContextCards,
    BleEncounters,
    GeocodingCache,
  ],
  daos: [
    EnvironmentsDao,
    TriggersDao,
    ContextCardsDao,
    BleEncountersDao,
    GeocodingCacheDao,
  ],
)
class SoproDatabase extends _$SoproDatabase {
  SoproDatabase() : super(_openConnection());

  // Construtor alternativo para testes — recebe a conexão de fora (in-memory)
  SoproDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 7;

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
          if (from < 5) {
            // Sprint F3-1: cache de resultados de geocoding (TTL 30 dias)
            await m.createTable(geocodingCache);
          }
          if (from < 6) {
            // Sprint F3-3: storagePolicy + placeId; remove expiresAt legado
            await m.addColumn(geocodingCache, geocodingCache.storagePolicy);
            await m.addColumn(geocodingCache, geocodingCache.placeId);
            // Remove expiresAt se existir (campo antigo)
            try {
              await customStatement('ALTER TABLE geocoding_cache DROP COLUMN expires_at');
            } catch (_) {}
          }
          if (from < 7) {
            // v7: title de Triggers perde o CHECK de comprimento mínimo.
            // Sem usuários em produção → recria a tabela do zero (não preserva dados).
            await m.deleteTable('triggers');
            await m.createTable(triggers);
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
