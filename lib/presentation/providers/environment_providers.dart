import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/environment_entity.dart';
import 'database_provider.dart';

// Observa todos os environments em tempo real.
// Atualiza automaticamente quando o banco muda (inserção, edição, exclusão).
final environmentsProvider = StreamProvider<List<EnvironmentEntity>>((ref) {
  return ref.watch(environmentRepositoryProvider).watchAll();
});

// Observa um environment específico pelo ID.
// Útil para a tela de detalhe do ambiente.
final environmentByIdProvider =
    StreamProvider.family<EnvironmentEntity?, String>((ref, id) async* {
  // Consulta única; re-executa se o provider for invalidado
  final entity = await ref.watch(environmentRepositoryProvider).getById(id);
  yield entity;
});
