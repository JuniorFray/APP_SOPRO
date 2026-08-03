// Motor de sincronização Drift ⇆ Supabase (Estágio 2.1 — só Home/Dart).
//
// Modelo LOCAL-FIRST: o SQLite/Drift continua sendo a fonte de leitura/escrita
// imediata (offline sempre funciona). Este motor roda POR TRÁS, sem que telas ou
// repositórios saibam que ele existe — empurra mudanças locais (PUSH) e puxa
// mudanças remotas (PULL) das 4 tabelas, quando (a) há sessão válida e (b) há
// conectividade. Conflito: last-write-wins por updatedAt.
//
// Sem novas dependências: HTTP via dart:io (mesmo padrão de AuthService/GroqStt),
// PostgREST cru. Sem pacote de conectividade — offline é detectado pela própria
// falha de rede (SocketException/timeout) e o sync vira no-op (fail-safe).
//
// NÃO faz (fora de escopo desta fase): Realtime, compartilhamento, sync do Overlay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../data/database/sopro_database.dart';
import '../auth/auth_service.dart';
import '../logging/core/logger.dart';
import 'package:drift/drift.dart' show Value;

class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const _timeout = Duration(seconds: 20);
  // Intervalo mínimo entre execuções — evita rajada de syncs no resume.
  static const _minInterval = Duration(seconds: 15);

  SoproDatabase? _db;
  StreamSubscription<AuthSession?>? _authSub;
  bool _running = false;
  DateTime? _lastRun;

  // Inicializa uma vez (AppInitializer). Guarda o banco e dispara um sync a cada
  // login (sessão passa a não-nula). Idempotente.
  void init(SoproDatabase db) {
    _db = db;
    _authSub ??= AuthService.instance.sessionStream.listen((session) {
      if (session != null) syncNow(reason: 'login');
    });
  }

  // Executa um ciclo completo de sync. Guardado: no-op se deslogado, sem config,
  // token vencido, já rodando, ou chamado cedo demais. Nunca lança (fail-safe).
  Future<void> syncNow({String reason = 'manual'}) async {
    final db = _db;
    if (db == null) return;
    final auth = AuthService.instance;
    final session = auth.currentSession;
    if (session == null || !auth.isConfigured) return; // deslogado/sem config
    if (session.isExpired) return; // token vencido → espera refresh no próximo start
    if (_running) return;
    if (_lastRun != null && DateTime.now().difference(_lastRun!) < _minInterval) {
      return;
    }
    _running = true;
    _lastRun = DateTime.now();
    try {
      Logger.debug('sync_start', feature: 'sync', action: reason);
      // PULL antes de PUSH: aplica o remoto mais novo (LWW) e então sobe o local.
      await _syncEnvironments(db, session);
      await _syncTriggers(db, session);
      await _syncReminders(db, session);
      await _syncShopping(db, session);
      Logger.debug('sync_done', feature: 'sync', action: reason);
    } catch (e) {
      // Qualquer falha (rede, parse, 4xx) é engolida — app segue 100% local.
      Logger.debug('sync_failed', feature: 'sync', action: reason, exception: e);
    } finally {
      _running = false;
    }
  }

  // ── Tabelas ────────────────────────────────────────────────────────────────

  Future<void> _syncEnvironments(SoproDatabase db, AuthSession s) async {
    final dao = db.environmentsDao;
    // PULL
    final remote = await _get('environments');
    if (remote != null) {
      final localById = {for (final r in await dao.allForSync()) r.id: r};
      for (final m in remote) {
        final id = m['id'] as String;
        final rUpd = _parseTs(m['updated_at']);
        final local = localById[id];
        if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
          // SEM pinImagePath: foto é local-only (não migra) — upsert não a toca.
          await dao.applyRemote(EnvironmentsCompanion(
            id: Value(id),
            name: Value(m['name'] as String),
            latitude: Value((m['latitude'] as num).toDouble()),
            longitude: Value((m['longitude'] as num).toDouble()),
            radiusMeters: Value((m['radius_meters'] as num).toDouble()),
            isMarket: Value(m['is_market'] as bool? ?? false),
            createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
            updatedAt: Value(rUpd),
            deletedAt: Value(_parseTs(m['deleted_at'])),
          ));
        }
      }
    }
    // PUSH
    final rows = (await dao.allForSync()).where((r) => r.updatedAt != null);
    final payload = [
      for (final r in rows)
        {
          'id': r.id,
          'user_id': s.userId,
          'name': r.name,
          'latitude': r.latitude,
          'longitude': r.longitude,
          'radius_meters': r.radiusMeters,
          'is_market': r.isMarket,
          'created_at': _fmt(r.createdAt),
          'updated_at': _fmt(r.updatedAt!),
          'deleted_at': r.deletedAt == null ? null : _fmt(r.deletedAt!),
        }
    ];
    if (payload.isNotEmpty) await _upsert('environments', payload);
  }

  Future<void> _syncTriggers(SoproDatabase db, AuthSession s) async {
    final dao = db.triggersDao;
    final remote = await _get('triggers');
    if (remote != null) {
      final localById = {for (final r in await dao.allForSync()) r.id: r};
      for (final m in remote) {
        final id = m['id'] as String;
        final rUpd = _parseTs(m['updated_at']);
        final local = localById[id];
        if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
          await dao.applyRemote(TriggersCompanion(
            id: Value(id),
            environmentId: Value(m['environment_id'] as String),
            title: Value(m['title'] as String? ?? ''),
            content: Value(m['content'] as String? ?? ''),
            isActive: Value(m['is_active'] as bool? ?? true),
            createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
            updatedAt: Value(rUpd),
            deletedAt: Value(_parseTs(m['deleted_at'])),
          ));
        }
      }
    }
    final rows = (await dao.allForSync()).where((r) => r.updatedAt != null);
    final payload = [
      for (final r in rows)
        {
          'id': r.id,
          'user_id': s.userId,
          'environment_id': r.environmentId,
          'title': r.title,
          'content': r.content,
          'is_active': r.isActive,
          'created_at': _fmt(r.createdAt),
          'updated_at': _fmt(r.updatedAt!),
          'deleted_at': r.deletedAt == null ? null : _fmt(r.deletedAt!),
        }
    ];
    if (payload.isNotEmpty) await _upsert('triggers', payload);
  }

  Future<void> _syncReminders(SoproDatabase db, AuthSession s) async {
    final dao = db.scheduledRemindersDao;
    final remote = await _get('scheduled_reminders');
    if (remote != null) {
      final localById = {for (final r in await dao.allForSync()) r.id: r};
      for (final m in remote) {
        final id = m['id'] as String;
        final rUpd = _parseTs(m['updated_at']);
        final local = localById[id];
        if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
          await dao.applyRemote(ScheduledRemindersCompanion(
            id: Value(id),
            title: Value(m['title'] as String? ?? ''),
            content: Value(m['content'] as String? ?? ''),
            scheduledAt: Value(_parseTs(m['scheduled_at']) ?? DateTime.now()),
            repeatRule: Value(m['repeat_rule'] as String? ?? 'daily'),
            repeatDaysOfWeek: Value(m['repeat_days_of_week'] as String? ?? ''),
            isActive: Value(m['is_active'] as bool? ?? true),
            alertMode: Value(m['alert_mode'] as String? ?? 'notification'),
            createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
            updatedAt: Value(rUpd),
            deletedAt: Value(_parseTs(m['deleted_at'])),
          ));
        }
      }
    }
    final rows = (await dao.allForSync()).where((r) => r.updatedAt != null);
    final payload = [
      for (final r in rows)
        {
          'id': r.id,
          'user_id': s.userId,
          'title': r.title,
          'content': r.content,
          'scheduled_at': _fmt(r.scheduledAt),
          'repeat_rule': r.repeatRule,
          'repeat_days_of_week': r.repeatDaysOfWeek,
          'is_active': r.isActive,
          'alert_mode': r.alertMode,
          'created_at': _fmt(r.createdAt),
          'updated_at': _fmt(r.updatedAt!),
          'deleted_at': r.deletedAt == null ? null : _fmt(r.deletedAt!),
        }
    ];
    if (payload.isNotEmpty) await _upsert('scheduled_reminders', payload);
  }

  Future<void> _syncShopping(SoproDatabase db, AuthSession s) async {
    final dao = db.shoppingListItemsDao;
    final remote = await _get('shopping_list_items');
    if (remote != null) {
      final localById = {for (final r in await dao.allForSync()) r.id: r};
      for (final m in remote) {
        final id = m['id'] as String;
        final rUpd = _parseTs(m['updated_at']);
        final local = localById[id];
        if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
          await dao.applyRemote(ShoppingListItemsCompanion(
            id: Value(id),
            environmentId: Value(m['environment_id'] as String),
            name: Value(m['name'] as String? ?? ''),
            isChecked: Value(m['is_checked'] as bool? ?? false),
            createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
            updatedAt: Value(rUpd),
            deletedAt: Value(_parseTs(m['deleted_at'])),
          ));
        }
      }
    }
    final rows = (await dao.allForSync()).where((r) => r.updatedAt != null);
    final payload = [
      for (final r in rows)
        {
          'id': r.id,
          'user_id': s.userId,
          'environment_id': r.environmentId,
          'name': r.name,
          'is_checked': r.isChecked,
          'created_at': _fmt(r.createdAt),
          'updated_at': _fmt(r.updatedAt!),
          'deleted_at': r.deletedAt == null ? null : _fmt(r.deletedAt!),
        }
    ];
    if (payload.isNotEmpty) await _upsert('shopping_list_items', payload);
  }

  // ── LWW ──────────────────────────────────────────────────────────────────
  // Remoto vence se a linha é nova localmente, ou se seu updatedAt é mais recente
  // que o local (local null conta como muito antigo).
  bool _remoteWins(DateTime? remoteUpd, DateTime? localUpd, {required bool isNew}) {
    if (isNew) return true;
    if (remoteUpd == null) return false;
    if (localUpd == null) return true;
    return remoteUpd.isAfter(localUpd);
  }

  // ── HTTP (PostgREST) ───────────────────────────────────────────────────────

  // GET de todas as linhas do usuário (RLS já filtra por user_id). Retorna a lista
  // de mapas, ou null se falhar (offline/erro) → chamador pula o PULL.
  Future<List<Map<String, dynamic>>?> _get(String table) async {
    final session = AuthService.instance.currentSession!;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('${AppConstants.supabaseUrl}/rest/v1/$table?select=*'))
          .timeout(_timeout);
      req.headers.set('apikey', AppConstants.supabaseAnonKey);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
      final resp = await req.close().timeout(_timeout);
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final list = jsonDecode(text) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null; // offline/erro → sem PULL nesta rodada
    } finally {
      client.close(force: true);
    }
  }

  // POST em lote com upsert (merge por PK id). return=minimal reduz payload de volta.
  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    final session = AuthService.instance.currentSession!;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('${AppConstants.supabaseUrl}/rest/v1/$table'))
          .timeout(_timeout);
      req.headers.set('apikey', AppConstants.supabaseAnonKey);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
      req.headers.contentType = ContentType.json;
      req.headers.set('Prefer', 'resolution=merge-duplicates,return=minimal');
      req.add(utf8.encode(jsonEncode(rows)));
      final resp = await req.close().timeout(_timeout);
      await resp.drain();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        Logger.debug('sync_push_rejected', feature: 'sync', action: table,
            payload: {'status': resp.statusCode.toString()});
      }
    } catch (_) {
      // offline/erro no PUSH — silencioso; a próxima rodada tenta de novo.
    } finally {
      client.close(force: true);
    }
  }

  // ── Timestamps (timestamptz ISO-8601) ───────────────────────────────────────
  String _fmt(DateTime dt) => dt.toUtc().toIso8601String();
  DateTime? _parseTs(Object? v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v)?.toLocal() : null;
}
