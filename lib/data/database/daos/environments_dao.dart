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

  // Retorna todos os environments cadastrados, ordenados por nome
  Future<List<Environment>> findAll() =>
      (select(environments)..orderBy([(e) => OrderingTerm(expression: e.name)]))
          .get();

  // Observa todos os environments em tempo real (Stream reativo com Riverpod)
  Stream<List<Environment>> watchAll() =>
      (select(environments)..orderBy([(e) => OrderingTerm(expression: e.name)]))
          .watch();

  // Busca um environment pelo UUID; retorna null se não encontrado
  Future<Environment?> findById(String id) =>
      (select(environments)..where((e) => e.id.equals(id))).getSingleOrNull();

  // Insere ou atualiza um environment (upsert por ID)
  Future<void> upsert(EnvironmentsCompanion entry) =>
      into(environments).insertOnConflictUpdate(entry);

  // Remove um environment pelo ID; os triggers vinculados são removidos em
  // cascade pelo banco (definido em triggers_table.dart via onDelete: cascade)
  Future<int> deleteById(String id) =>
      (delete(environments)..where((e) => e.id.equals(id))).go();
}
