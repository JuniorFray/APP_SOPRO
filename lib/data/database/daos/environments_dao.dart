import 'package:drift/drift.dart';

import '../sopro_database.dart';
import '../tables/environments_table.dart';

// DAO (Data Access Object) para a tabela de Environments.
// Concentra todas as queries SQL relacionadas a ambientes físicos.
// A anotação @DriftAccessor declara quais tabelas este DAO acessa.
part 'environments_dao.g.dart';

@DriftAccessor(tables: [Environments])
class EnvironmentsDao extends DatabaseAccessor<SoproDatabase>
    with _$EnvironmentsDaoMixin {
  EnvironmentsDao(super.db);

  // Retorna todos os environments visíveis (exclui tombstones), ordenados por nome
  Future<List<Environment>> findAll() =>
      (select(environments)
            ..where((e) => e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm(expression: e.name)]))
          .get();

  // Observa os environments visíveis em tempo real (Stream reativo com Riverpod)
  Stream<List<Environment>> watchAll() =>
      (select(environments)
            ..where((e) => e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm(expression: e.name)]))
          .watch();

  // Busca um environment visível pelo UUID; retorna null se não encontrado/excluído
  Future<Environment?> findById(String id) =>
      (select(environments)
            ..where((e) => e.id.equals(id) & e.deletedAt.isNull()))
          .getSingleOrNull();

  // Insere ou atualiza um environment (upsert por ID). Carimba updatedAt=agora
  // para o motor de sync empurrar a mudança (escrita originada no app).
  Future<void> upsert(EnvironmentsCompanion entry) =>
      into(environments).insertOnConflictUpdate(
          entry.copyWith(updatedAt: Value(DateTime.now())));

  // Atualiza apenas a flag isMarket sem tocar nos demais campos
  Future<bool> setIsMarket(String id, {required bool isMarket}) =>
      (update(environments)..where((e) => e.id.equals(id)))
          .write(EnvironmentsCompanion(
              isMarket: Value(isMarket), updatedAt: Value(DateTime.now())))
          .then((count) => count > 0);

  // Atualiza apenas o caminho da foto do pin (null remove a foto) sem tocar nos
  // demais campos. Value(path) grava; Value(null) volta à arte Sopro padrão.
  Future<bool> setPinImagePath(String id, String? path) =>
      (update(environments)..where((e) => e.id.equals(id)))
          .write(EnvironmentsCompanion(
              pinImagePath: Value(path), updatedAt: Value(DateTime.now())))
          .then((count) => count > 0);

  // Soft delete pelo ID: marca deletedAt (não remove a linha) para o tombstone
  // subir no sync. Cascade manual dos triggers do ambiente — o cascade físico do
  // FK só dispara em DELETE real, então tombstonamos os filhos aqui.
  Future<int> deleteById(String id) async {
    final now = DateTime.now();
    final db = attachedDatabase;
    await (db.update(db.triggers)
          ..where((t) => t.environmentId.equals(id) & t.deletedAt.isNull()))
        .write(TriggersCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    return (update(environments)..where((e) => e.id.equals(id)))
        .write(EnvironmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  // ── Motor de sync (Estágio 2.1) ────────────────────────────────────────────
  // Todas as linhas, INCLUINDO tombstones (para o PUSH propagar exclusões).
  Future<List<Environment>> allForSync() => select(environments).get();

  // Leitura crua por ID (ignora o filtro de tombstone) — usada no LWW do PULL.
  Future<Environment?> findByIdRaw(String id) =>
      (select(environments)..where((e) => e.id.equals(id))).getSingleOrNull();

  // Aplica uma linha remota como-está (preserva updatedAt/deletedAt do servidor).
  // O companion vem SEM pinImagePath (foto é local-only, não migra) — o upsert
  // não toca nessa coluna, preservando a foto local.
  Future<void> applyRemote(EnvironmentsCompanion entry) =>
      into(environments).insertOnConflictUpdate(entry);
}
