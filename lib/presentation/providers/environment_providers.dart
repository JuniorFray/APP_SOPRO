import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/environment_entity.dart';
import 'database_provider.dart';

// Observa todos os environments em tempo real.
// Atualiza automaticamente quando o banco muda (inserção, edição, exclusão).
final environmentsProvider = StreamProvider<List<EnvironmentEntity>>((ref) {
  return ref.watch(environmentRepositoryProvider).watchAll();
});

// Observa um environment específico pelo ID em tempo real.
// Mapeia o stream de todos os ambientes para retornar apenas o de [id].
// Atualiza automaticamente quando o ambiente é editado ou excluído.
// Retorna null se o ambiente não existir (ex: excluído externamente).
final environmentByIdProvider =
    StreamProvider.family<EnvironmentEntity?, String>((ref, id) {
  return ref.watch(environmentRepositoryProvider).watchAll().map(
    (list) {
      // firstWhere lança se não encontrar; tratamos com try/catch
      try {
        return list.firstWhere((e) => e.id == id);
      } catch (_) {
        return null;
      }
    },
  );
});
