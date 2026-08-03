// Cliente de autenticação Supabase (GoTrue) via REST puro.
//
// Decisão de arquitetura: NÃO usamos o pacote supabase_flutter. O projeto já
// fala com o Supabase por REST cru (SupabaseSink.kt / logging) e todo HTTP Dart
// usa dart:io HttpClient sem adicionar dependência (ver GroqSttService). Auth
// email/senha é um punhado de endpoints GoTrue simples — mantemos o mesmo padrão
// e evitamos risco de resolução de versão neste projeto com pins delicados.
//
// Persistência de sessão: os tokens são gravados em SharedPreferences com chaves
// SEM prefixo (o plugin adiciona "flutter." ao persistir). Assim o Overlay nativo
// (Kotlin, sem Flutter Engine) lê "flutter.sopro_access_token" etc. — mesmo padrão
// já usado para gemini_api_key / openweather_api_key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../logging/core/logger.dart';

// Chaves de SharedPreferences compartilhadas com o Overlay nativo.
// Overlay lê as mesmas com o prefixo "flutter." (ver SupabaseAuth.kt).
class AuthPrefKeys {
  AuthPrefKeys._();
  static const accessToken  = 'sopro_access_token';
  static const refreshToken = 'sopro_refresh_token';
  // Expiração absoluta em SEGUNDOS desde epoch, gravada como String para não
  // depender de setInt/getLong entre Dart e Kotlin (String é lida igual dos dois lados).
  static const expiresAt    = 'sopro_token_expires_at';
  static const userEmail    = 'sopro_user_email';
  static const userId       = 'sopro_user_id';
}

// Sessão autenticada em memória (espelho do que está persistido).
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  // Considera "quase expirado" 60s antes do fim — margem para a chamada seguinte.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));
}

// Resultado de uma operação de auth: sucesso (session != null quando há sessão)
// ou falha (errorCode preenchido). Para signup com confirmação de e-mail exigida,
// success == true e session == null e needsEmailConfirm == true.
class AuthResult {
  final bool success;
  final AuthSession? session;
  final bool needsEmailConfirm;
  final String? errorCode; // mapeado para string amigável na UI

  const AuthResult._({
    required this.success,
    this.session,
    this.needsEmailConfirm = false,
    this.errorCode,
  });

  factory AuthResult.ok(AuthSession? session, {bool needsEmailConfirm = false}) =>
      AuthResult._(success: true, session: session, needsEmailConfirm: needsEmailConfirm);
  factory AuthResult.fail(String errorCode) =>
      AuthResult._(success: false, errorCode: errorCode);
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _timeout = Duration(seconds: 15);

  // Sessão corrente (null = deslogado). Atualizada por todos os fluxos.
  AuthSession? _session;
  AuthSession? get currentSession => _session;
  bool get isLoggedIn => _session != null;

  // Notifica ouvintes (provider Riverpod) quando a sessão muda.
  final _controller = StreamController<AuthSession?>.broadcast();
  Stream<AuthSession?> get sessionStream => _controller.stream;

  String get _base => AppConstants.supabaseUrl;
  String get _key  => AppConstants.supabaseAnonKey;
  bool get isConfigured => _base.isNotEmpty && _key.isNotEmpty;

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  // Restaura a sessão persistida e, se o token estiver perto de expirar, faz o
  // refresh. Chamado no startup (AppInitializer). Best-effort: falha de rede
  // apenas mantém a sessão local (o Overlay/App usam o token até o próximo refresh).
  Future<void> restoreAndRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final access  = prefs.getString(AuthPrefKeys.accessToken);
    final refresh = prefs.getString(AuthPrefKeys.refreshToken);
    final expStr  = prefs.getString(AuthPrefKeys.expiresAt);
    if (access == null || refresh == null || expStr == null) return;

    final expSecs = int.tryParse(expStr) ?? 0;
    _session = AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expSecs * 1000),
      userId: prefs.getString(AuthPrefKeys.userId) ?? '',
      email: prefs.getString(AuthPrefKeys.userEmail) ?? '',
    );
    _controller.add(_session);

    if (_session!.isExpired && isConfigured) {
      try {
        await _refresh(refresh);
      } catch (e) {
        Logger.debug('auth_restore_refresh_failed', feature: 'auth',
            action: 'restore', exception: e);
      }
    }
  }

  // ── Operações públicas ────────────────────────────────────────────────────

  // Cadastro email/senha. Se o Supabase exigir confirmação de e-mail, a resposta
  // vem SEM access_token → devolvemos needsEmailConfirm (usuário confirma e depois
  // faz login). Se confirmação estiver desligada, já vem a sessão e logamos direto.
  Future<AuthResult> signUp(String email, String password) async {
    if (!isConfigured) return AuthResult.fail('unavailable');
    try {
      final (status, json) = await _post(
        '/auth/v1/signup',
        body: {'email': email, 'password': password},
      );
      if (status >= 200 && status < 300) {
        final session = _sessionFromJson(json);
        if (session != null) {
          await _persist(session);
          return AuthResult.ok(session);
        }
        // 200 sem access_token → confirmação de e-mail exigida pelo projeto.
        return AuthResult.ok(null, needsEmailConfirm: true);
      }
      return AuthResult.fail(_mapError(status, json, signup: true));
    } on SocketException {
      return AuthResult.fail('no_internet');
    } catch (e) {
      Logger.warn('auth_signup_error', feature: 'auth', action: 'signUp', exception: e);
      return AuthResult.fail('generic');
    }
  }

  // Login email/senha (grant_type=password).
  Future<AuthResult> signIn(String email, String password) async {
    if (!isConfigured) return AuthResult.fail('unavailable');
    try {
      final (status, json) = await _post(
        '/auth/v1/token?grant_type=password',
        body: {'email': email, 'password': password},
      );
      if (status >= 200 && status < 300) {
        final session = _sessionFromJson(json);
        if (session != null) {
          await _persist(session);
          return AuthResult.ok(session);
        }
        return AuthResult.fail('generic');
      }
      return AuthResult.fail(_mapError(status, json));
    } on SocketException {
      return AuthResult.fail('no_internet');
    } catch (e) {
      Logger.warn('auth_login_error', feature: 'auth', action: 'signIn', exception: e);
      return AuthResult.fail('generic');
    }
  }

  // Envia o e-mail de recuperação de senha (GoTrue /recover). Fail-open: sempre
  // exibimos a mesma mensagem neutra na UI para não vazar existência de conta.
  Future<AuthResult> recoverPassword(String email) async {
    if (!isConfigured) return AuthResult.fail('unavailable');
    try {
      final (status, json) = await _post(
        '/auth/v1/recover',
        body: {'email': email},
      );
      if (status >= 200 && status < 300) return AuthResult.ok(null);
      return AuthResult.fail(_mapError(status, json));
    } on SocketException {
      return AuthResult.fail('no_internet');
    } catch (e) {
      Logger.warn('auth_recover_error', feature: 'auth', action: 'recover', exception: e);
      return AuthResult.fail('generic');
    }
  }

  // Logout: revoga a sessão no servidor (best-effort) e limpa o estado local +
  // tokens persistidos (o Overlay deixa de ver token válido).
  Future<void> signOut() async {
    final token = _session?.accessToken;
    _session = null;
    await _clearPersisted();
    _controller.add(null);
    if (token != null && isConfigured) {
      try {
        await _post('/auth/v1/logout', body: const {}, bearer: token);
      } catch (_) {/* revogação é best-effort */}
    }
  }

  // ── Refresh de token ──────────────────────────────────────────────────────

  // Troca o refresh_token por um novo par de tokens. Usado no startup quando o
  // access_token está vencido. O Overlay nativo tem sua própria cópia deste fluxo.
  Future<AuthSession?> _refresh(String refreshToken) async {
    final (status, json) = await _post(
      '/auth/v1/token?grant_type=refresh_token',
      body: {'refresh_token': refreshToken},
    );
    if (status >= 200 && status < 300) {
      final session = _sessionFromJson(json);
      if (session != null) {
        await _persist(session);
        return session;
      }
    }
    // refresh_token inválido/revogado → sessão morta. Limpa para evitar loop.
    if (status == 400 || status == 401) {
      _session = null;
      await _clearPersisted();
      _controller.add(null);
    }
    return null;
  }

  // ── Helpers HTTP (dart:io, mesmo padrão do GroqSttService) ─────────────────

  Future<(int, Map<String, dynamic>)> _post(
    String path, {
    required Map<String, dynamic> body,
    String? bearer,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('$_base$path'))
          .timeout(_timeout);
      req.headers.set('apikey', _key);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${bearer ?? _key}');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close().timeout(_timeout);
      final text = await resp.transform(utf8.decoder).join();
      final Map<String, dynamic> parsed =
          text.isEmpty ? {} : (jsonDecode(text) as Map<String, dynamic>);
      return (resp.statusCode, parsed);
    } finally {
      client.close(force: true);
    }
  }

  // Monta a sessão a partir do JSON de token do GoTrue. Retorna null se não houver
  // access_token (ex.: signup com confirmação exigida).
  AuthSession? _sessionFromJson(Map<String, dynamic> json) {
    final access = json['access_token'] as String?;
    final refresh = json['refresh_token'] as String?;
    if (access == null || refresh == null) return null;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    final user = json['user'] as Map<String, dynamic>?;
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: (user?['id'] as String?) ?? '',
      email: (user?['email'] as String?) ?? '',
    );
  }

  // Mapeia status + corpo GoTrue para um código de erro curto (traduzido na UI).
  String _mapError(int status, Map<String, dynamic> json, {bool signup = false}) {
    final msg = ((json['error_description'] ?? json['msg'] ?? json['error'] ?? '')
            as Object)
        .toString()
        .toLowerCase();
    if (signup && (msg.contains('already') || status == 422)) return 'email_taken';
    if (status == 400 && msg.contains('invalid')) return 'invalid_credentials';
    if (status == 400 || status == 401) return 'invalid_credentials';
    return 'generic';
  }

  // ── Persistência (espelhada para o Overlay) ────────────────────────────────

  Future<void> _persist(AuthSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthPrefKeys.accessToken, session.accessToken);
    await prefs.setString(AuthPrefKeys.refreshToken, session.refreshToken);
    await prefs.setString(AuthPrefKeys.expiresAt,
        (session.expiresAt.millisecondsSinceEpoch ~/ 1000).toString());
    await prefs.setString(AuthPrefKeys.userEmail, session.email);
    await prefs.setString(AuthPrefKeys.userId, session.userId);
    _controller.add(session);
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthPrefKeys.accessToken);
    await prefs.remove(AuthPrefKeys.refreshToken);
    await prefs.remove(AuthPrefKeys.expiresAt);
    await prefs.remove(AuthPrefKeys.userEmail);
    await prefs.remove(AuthPrefKeys.userId);
  }
}
