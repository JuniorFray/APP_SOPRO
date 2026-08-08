// Serviço REST cru (dart:io) para a tabela environment_shares (Fase 3).
// Mesmo padrão do SyncEngine/AuthService — sem supabase_flutter, PostgREST puro.
// Todas as operações exigem sessão válida; a RLS do servidor faz o controle fino
// de quem pode o quê (dono via shares_owner_all, convidado via shares_guest_*).
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../auth/auth_service.dart';
import '../logging/core/logger.dart';

// Modelo de uma linha de environment_shares.
class EnvironmentShare {
  final String id;
  final String environmentId;
  final String ownerId;
  final String sharedWithId;
  final String sharedWithEmail;
  final bool includeTriggers;
  final String status; // 'active' | 'revoked'

  const EnvironmentShare({
    required this.id,
    required this.environmentId,
    required this.ownerId,
    required this.sharedWithId,
    required this.sharedWithEmail,
    required this.includeTriggers,
    required this.status,
  });

  factory EnvironmentShare.fromJson(Map<String, dynamic> m) => EnvironmentShare(
        id: m['id'] as String,
        environmentId: m['environment_id'] as String,
        ownerId: m['owner_id'] as String,
        sharedWithId: m['shared_with_id'] as String,
        sharedWithEmail: (m['shared_with_email'] as String?) ?? '',
        includeTriggers: m['include_triggers'] as bool? ?? false,
        status: (m['status'] as String?) ?? 'active',
      );
}

class SharesService {
  SharesService._();
  static final SharesService instance = SharesService._();

  static const _timeout = Duration(seconds: 20);
  static const _table = 'environment_shares';

  String get _base => AppConstants.supabaseUrl;
  String get _key => AppConstants.supabaseAnonKey;

  // ── Operações (visão do dono) ───────────────────────────────────────────────

  // Cria (ou reativa) um compartilhamento. owner_id = usuário atual.
  // UPSERT no par único (environment_id, shared_with_id): se a pessoa já foi
  // convidada e depois revogada/saiu, a linha antiga (status='revoked') ainda
  // ocupa o par único — um INSERT puro bateria 409 Conflict. merge-duplicates
  // reativa a linha existente (status='active') em vez de falhar.
  Future<bool> create({
    required String environmentId,
    required String sharedWithId,
    required String sharedWithEmail,
    required bool includeTriggers,
  }) async {
    final s = AuthService.instance.currentSession;
    if (s == null) return false;
    return _post([
      {
        'environment_id': environmentId,
        'owner_id': s.userId,
        'shared_with_id': sharedWithId,
        'shared_with_email': sharedWithEmail,
        'include_triggers': includeTriggers,
        'status': 'active',
      }
    ], onConflict: 'environment_id,shared_with_id');
  }

  // Liga/desliga "compartilhar gatilhos" de um share existente.
  Future<bool> setIncludeTriggers(String shareId, bool value) =>
      _patch(shareId, {'include_triggers': value});

  // Revoga um compartilhamento. Serve tanto pro dono (shares_owner_all) quanto pro
  // convidado saindo sozinho (shares_guest_leave, decisão #5) — em ambos vira
  // status='revoked'. Soft-revoke: a linha permanece (histórico).
  Future<bool> revoke(String shareId) => _patch(shareId, {'status': 'revoked'});

  // Alias semântico pro convidado sair sozinho de um compartilhamento (decisão #5).
  Future<bool> leave(String shareId) => revoke(shareId);

  // ── Leituras ────────────────────────────────────────────────────────────────

  // Compartilhamentos ATIVOS de um ambiente (visão do dono: quem tem acesso).
  Future<List<EnvironmentShare>> forEnvironment(String environmentId) =>
      _get('environment_id=eq.$environmentId&status=eq.active');

  // Compartilhamentos que EU recebi (visão do convidado — "Compartilharam comigo").
  Future<List<EnvironmentShare>> incoming() {
    final s = AuthService.instance.currentSession;
    if (s == null) return Future.value(const []);
    return _get('shared_with_id=eq.${s.userId}&status=eq.active');
  }

  // Compartilhamentos que EU fiz (visão do dono — "Compartilhei").
  Future<List<EnvironmentShare>> outgoing() {
    final s = AuthService.instance.currentSession;
    if (s == null) return Future.value(const []);
    return _get('owner_id=eq.${s.userId}&status=eq.active');
  }

  // ── HTTP (PostgREST) ─────────────────────────────────────────────────────────

  Future<List<EnvironmentShare>> _get(String filter) async {
    final s = AuthService.instance.currentSession;
    if (s == null) return const [];
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('$_base/rest/v1/$_table?select=*&$filter'))
          .timeout(_timeout);
      req.headers.set('apikey', _key);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${s.accessToken}');
      final resp = await req.close().timeout(_timeout);
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => EnvironmentShare.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Logger.debug('shares_get_failed',
          feature: 'sharing', action: 'get', exception: e);
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  // [onConflict] != null → vira UPSERT (on_conflict + resolution=merge-duplicates),
  // reativando a linha existente do par único em vez de colidir com a UNIQUE.
  Future<bool> _post(List<Map<String, dynamic>> rows, {String? onConflict}) async {
    final s = AuthService.instance.currentSession;
    if (s == null) return false;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final url = onConflict == null
          ? '$_base/rest/v1/$_table'
          : '$_base/rest/v1/$_table?on_conflict=$onConflict';
      final req = await client.postUrl(Uri.parse(url)).timeout(_timeout);
      req.headers.set('apikey', _key);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${s.accessToken}');
      req.headers.contentType = ContentType.json;
      req.headers.set(
        'Prefer',
        onConflict == null
            ? 'return=minimal'
            : 'return=minimal,resolution=merge-duplicates',
      );
      req.add(utf8.encode(jsonEncode(rows)));
      final resp = await req.close().timeout(_timeout);
      await resp.drain();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      Logger.debug('shares_post_failed',
          feature: 'sharing', action: 'post', exception: e);
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _patch(String shareId, Map<String, dynamic> patch) async {
    final s = AuthService.instance.currentSession;
    if (s == null) return false;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .openUrl('PATCH', Uri.parse('$_base/rest/v1/$_table?id=eq.$shareId'))
          .timeout(_timeout);
      req.headers.set('apikey', _key);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${s.accessToken}');
      req.headers.contentType = ContentType.json;
      req.headers.set('Prefer', 'return=minimal');
      req.add(utf8.encode(jsonEncode(patch)));
      final resp = await req.close().timeout(_timeout);
      await resp.drain();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      Logger.debug('shares_patch_failed',
          feature: 'sharing', action: 'patch', exception: e);
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
