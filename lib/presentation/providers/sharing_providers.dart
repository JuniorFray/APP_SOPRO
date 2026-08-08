import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/auth/auth_service.dart';
import '../../infrastructure/sharing/shares_service.dart';
import 'auth_providers.dart';

// Providers de compartilhamento (Fase 3). Todos best-effort: em offline/erro os
// serviços devolvem lista vazia / null, então a UI degrada sem quebrar.

// Singleton do serviço REST de shares.
final sharesServiceProvider =
    Provider<SharesService>((ref) => SharesService.instance);

// Quem tem acesso a um ambiente (visão do dono). ref.invalidate após criar/revogar.
final sharesByEnvironmentProvider =
    FutureProvider.family<List<EnvironmentShare>, String>((ref, envId) {
  return ref.watch(sharesServiceProvider).forEnvironment(envId);
});

// Compartilhamentos recebidos (visão do convidado — "Compartilharam comigo").
final incomingSharesProvider = FutureProvider<List<EnvironmentShare>>((ref) {
  return ref.watch(sharesServiceProvider).incoming();
});

// Compartilhamentos que eu fiz (visão do dono — "Compartilhei").
final outgoingSharesProvider = FutureProvider<List<EnvironmentShare>>((ref) {
  return ref.watch(sharesServiceProvider).outgoing();
});

// Resolve e-mail -> perfil de conta EXISTENTE (null = sem conta Sopro). Usado no
// convite. Family pelo e-mail; a UI chama com debounce ou no submit.
final resolveUserByEmailProvider =
    FutureProvider.family<SoproProfile?, String>((ref, email) {
  return ref.watch(authServiceProvider).resolveUserByEmail(email);
});
