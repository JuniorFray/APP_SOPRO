import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages — sqlite3 vem transitivo do drift; só teste
import 'package:sqlite3/sqlite3.dart';

import 'package:sopro/data/database/sopro_database.dart';

// Teste da migração Drift v15 → v16 (Sync 2.1) contra um banco JÁ POPULADO.
// Cria um arquivo no shape v15 (sem updated_at/deleted_at), insere dados, e abre
// a SoproDatabase real — o que dispara onUpgrade(15,16). Verifica que:
//  • as colunas novas passam a existir,
//  • updated_at é preenchido com created_at nas linhas existentes (backfill),
//  • nenhum dado é perdido.
void main() {
  test('migração v15->v16 adiciona colunas, faz backfill e preserva dados', () async {
    final dir = Directory.systemTemp.createTempSync('sopro_mig_test');
    final file = File('${dir.path}/sopro.db');

    // 1. Cria o banco no shape v15 (só as 4 tabelas tocadas pela migração) + dados.
    final raw = sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE environments (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        latitude REAL NOT NULL, longitude REAL NOT NULL, radius_meters REAL NOT NULL,
        created_at INTEGER NOT NULL, is_market INTEGER NOT NULL DEFAULT 0,
        pin_image_path TEXT);
      CREATE TABLE triggers (
        id TEXT NOT NULL PRIMARY KEY, environment_id TEXT NOT NULL,
        title TEXT NOT NULL, content TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);
      CREATE TABLE scheduled_reminders (
        id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '', scheduled_at INTEGER NOT NULL,
        repeat_rule TEXT NOT NULL DEFAULT 'daily',
        repeat_days_of_week TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        alert_mode TEXT NOT NULL DEFAULT 'notification', created_at INTEGER NOT NULL);
      CREATE TABLE shopping_list_items (
        id TEXT NOT NULL PRIMARY KEY, environment_id TEXT NOT NULL,
        name TEXT NOT NULL, is_checked INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL);
    ''');
    raw.execute(
        "INSERT INTO environments (id,name,latitude,longitude,radius_meters,created_at,is_market) "
        "VALUES ('e1','Casa',-23.5,-46.6,100,1700000000,0)");
    raw.execute(
        "INSERT INTO triggers (id,environment_id,title,content,is_active,created_at) "
        "VALUES ('t1','e1','Tirar lixo','',1,1700000001)");
    // Linha "legada" do Overlay antigo: created_at em MILISSEGUNDOS (bug pré-2.2).
    raw.execute(
        "INSERT INTO environments (id,name,latitude,longitude,radius_meters,created_at,is_market) "
        "VALUES ('e2','Obra',-23.6,-46.7,100,1700000000000,0)");
    raw.execute('PRAGMA user_version = 15;');
    raw.dispose();

    // 2. Abre a SoproDatabase real → executa onUpgrade(15,16).
    final db = SoproDatabase.forTesting(NativeDatabase(file));

    // 3. Backfill v16: updated_at == created_at; deleted_at nulo (linha em segundos).
    final e1 = (await db
            .customSelect("SELECT created_at, updated_at, deleted_at FROM environments WHERE id='e1'")
            .get())
        .single;
    expect(e1.data['updated_at'], e1.data['created_at']);
    expect(e1.data['created_at'], 1700000000); // já em segundos → intacto
    expect(e1.data['deleted_at'], isNull);

    final trg = (await db
            .customSelect('SELECT created_at, updated_at FROM triggers')
            .get())
        .single;
    expect(trg.data['updated_at'], trg.data['created_at']);

    // 4. Normalização v17: linha legada em MS vira SEGUNDOS (created_at e updated_at).
    final e2 = (await db
            .customSelect("SELECT created_at, updated_at FROM environments WHERE id='e2'")
            .get())
        .single;
    expect(e2.data['created_at'], 1700000000);
    expect(e2.data['updated_at'], 1700000000);

    // 5. Dados preservados e visíveis (soft-delete não afeta linhas ativas).
    final envs = await db.environmentsDao.findAll();
    expect(envs.length, 2);
    expect(envs.map((e) => e.name), containsAll(['Casa', 'Obra']));

    await db.close();
    dir.deleteSync(recursive: true);
  });
}
