import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/shopping_list_item_entity.dart';
import 'database_provider.dart';

// Observa os itens da lista de compras de um mercado em tempo real.
// Recebe o environmentId como parâmetro de família.
final shoppingListByEnvironmentProvider =
    StreamProvider.family<List<ShoppingListItemEntity>, String>(
        (ref, environmentId) {
  return ref
      .watch(shoppingListRepositoryProvider)
      .watchByEnvironment(environmentId);
});
