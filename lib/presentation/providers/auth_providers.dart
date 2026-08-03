import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/auth/auth_service.dart';

// Acesso ao singleton do AuthService.
final authServiceProvider = Provider<AuthService>((ref) => AuthService.instance);

// Estado reativo da sessão (null = deslogado). Semeia com a sessão atual do
// serviço e acompanha o stream de mudanças (login/logout/refresh). As telas
// (Configurações, Conta) observam este provider para trocar de UI sem setState.
final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession?>((ref) {
  return AuthSessionNotifier(ref.watch(authServiceProvider));
});

class AuthSessionNotifier extends StateNotifier<AuthSession?> {
  final AuthService _service;
  late final StreamSubscription<AuthSession?> _sub;

  AuthSessionNotifier(this._service) : super(_service.currentSession) {
    _sub = _service.sessionStream.listen((s) => state = s);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
