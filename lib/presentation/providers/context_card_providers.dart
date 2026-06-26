import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/context_card_entity.dart';
import 'database_provider.dart';

// Observa o ContextCard ativo do usuário em tempo real.
// Usado pela tela de perfil e pelo serviço BLE para montar o payload de anúncio.
final activeContextCardProvider = StreamProvider<ContextCardEntity?>((ref) {
  return ref.watch(contextCardRepositoryProvider).watchActive();
});
