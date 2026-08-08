// Motor de sincronização Drift ⇆ Supabase (Estágio 2.1 — só Home/Dart).
//
// Modelo LOCAL-FIRST: o SQLite/Drift continua sendo a fonte de leitura/escrita
// imediata (offline sempre funciona). Este motor roda POR TRÁS, sem que telas ou
// repositórios saibam que ele existe — empurra mudanças locais (PUSH) e puxa
// mudanças remotas (PULL) das 4 tabelas, quando (a) há sessão válida e (b) há
// conectividade. Conflito: last-write-wins por updatedAt.
//
// Troca de conta no mesmo aparelho: o banco local é de UMA conta por vez. Ao
// logar com dono diferente do último, reconcileAccount() limpa as 4 tabelas e o
// PULL repopula com os dados da conta nova (padrão comum de apps com conta). Isso
// mantém o PUSH correto: como o banco só tem linhas do dono atual, carimbar
// user_id da sessão em cada linha nunca vaza dado entre contas.
//
// Sem novas dependências: HTTP via dart:io (mesmo padrão de AuthService/GroqStt),
// PostgREST cru. Sem pacote de conectividade — offline é detectado pela própria
// falha de rede (SocketException/timeout) e o sync vira no-op (fail-safe).
//
// NÃO faz (fora de escopo desta fase): Realtime, compartilhamento, sync do Overlay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/sopro_database.dart';
import '../auth/auth_service.dart';
import '../geofence/native_geofence_service.dart';
import '../logging/core/logger.dart';
// Import completo do drift: além de Value, traz os operadores de Expression
// (&, isNull, isNotNull) usados nas queries de reconciliação/detach da Fase 3.
import 'package:drift/drift.dart';

class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const _timeout = Duration(seconds: 20);
  // Intervalo mínimo entre execuções — evita rajada de syncs no resume.
  static const _minInterval = Duration(seconds: 15);
  // Chave (SharedPreferences, só Dart) do último dono do banco neste aparelho.
  // Sobrevive ao logout de propósito (signOut NÃO a apaga) para detectar troca de
  // conta no próximo login. Não tem prefixo "flutter." — não é lida pelo Overlay.
  static const _lastOwnerKey = 'sync_last_owner_id';

  SoproDatabase? _db;
  StreamSubscription<AuthSession?>? _authSub;
  bool _running = false;
  DateTime? _lastRun;
  // Usado na reconciliação de compartilhamento (Fase 3) para trocar o geofence de
  // um ambiente compartilhado revogado pelo geofence do novo ambiente próprio.
  final _geofence = NativeGeofenceService();

  // Inicializa uma vez (AppInitializer). Guarda o banco e, a cada login (sessão
  // passa a não-nula), reconcilia a conta (detecta troca → wipe + PULL). Idempotente.
  void init(SoproDatabase db) {
    _db = db;
    _authSub ??= AuthService.instance.sessionStream.listen((session) {
      if (session != null) reconcileAccount();
    });
  }

  // Chamado quando uma sessão é estabelecida (login em runtime ou restauração no
  // boot). Detecta TROCA de conta: se o dono desta sessão difere do último dono
  // que usou o banco neste aparelho, limpa as 4 tabelas locais (hard delete) para
  // não misturar contas — o PULL a seguir repopula com os dados da conta nova.
  // Primeiro login de sempre (sem dono anterior) e re-login da MESMA conta não
  // limpam nada. Uso local puro (nunca logou) nunca chega aqui.
  Future<void> reconcileAccount() async {
    final db = _db;
    if (db == null) return;
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    final lastOwner = prefs.getString(_lastOwnerKey);
    final switched =
        lastOwner != null && lastOwner.isNotEmpty && lastOwner != session.userId;
    if (switched) {
      await db.wipeSyncedTables();
      Logger.info('account_switch_wipe', feature: 'sync', action: 'reconcile');
    }
    await prefs.setString(_lastOwnerKey, session.userId);
    // force: garante o PULL imediato mesmo logo após um sync de startup (throttle).
    await syncNow(reason: switched ? 'account_switch' : 'login', force: true);
  }

  // Executa um ciclo completo de sync. Guardado: no-op se deslogado, sem config,
  // token vencido, já rodando, ou chamado cedo demais (salvo force). Nunca lança.
  Future<void> syncNow({String reason = 'manual', bool force = false}) async {
    final db = _db;
    if (db == null) return;
    final auth = AuthService.instance;
    final session = auth.currentSession;
    if (session == null || !auth.isConfigured) return; // deslogado/sem config
    if (session.isExpired) return; // token vencido → espera refresh no próximo start
    if (_running) return;
    if (!force &&
        _lastRun != null &&
        DateTime.now().difference(_lastRun!) < _minInterval) {
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

  // PUSH final das pendências locais sob a sessão ATUAL, antes de o logout limpar
  // a sessão. Ignora o throttle e NÃO faz PULL. Retorna false se algum envio falhou
  // (offline/HTTP) — o chamador avisa que dados podem não ter subido. Nunca lança.
  Future<bool> flush() async {
    final db = _db;
    if (db == null) return true;
    final auth = AuthService.instance;
    final session = auth.currentSession;
    if (session == null || !auth.isConfigured || session.isExpired) return true;
    var ok = true;
    try {
      ok = await _pushEnvironments(db, session) && ok;
      ok = await _pushTriggers(db, session) && ok;
      ok = await _pushReminders(db, session) && ok;
      ok = await _pushShopping(db, session) && ok;
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  // ── Tabelas (cada uma: PULL depois PUSH) ─────────────────────────────────────

  Future<void> _syncEnvironments(SoproDatabase db, AuthSession s) async {
    await _pullEnvironments(db, s);
    await _pushEnvironments(db, s);
  }

  Future<void> _pullEnvironments(SoproDatabase db, AuthSession s) async {
    final dao = db.environmentsDao;
    final remote = await _get('environments');
    if (remote == null) return;
    final localById = {for (final r in await dao.allForSync()) r.id: r};
    final remoteIds = <String>{};
    for (final m in remote) {
      final id = m['id'] as String;
      remoteIds.add(id);
      final rUpd = _parseTs(m['updated_at']);
      final local = localById[id];
      if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
        // ownerId: null se a linha é minha; user_id remoto quando é cópia de um
        // ambiente compartilhado por OUTRO dono (read-only). Distingue o que o
        // PUSH pode reenviar e o que a reconciliação pode descartar/detachar.
        final remoteOwner = m['user_id'] as String?;
        final ownerId =
            (remoteOwner != null && remoteOwner != s.userId) ? remoteOwner : null;
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
          ownerId: Value(ownerId),
        ));
      }
    }
    // Reconciliação (Fase 3): cópia read-only (ownerId != null) que não veio mais
    // no remoto = compartilhamento revogado/removido → vira ambiente próprio do
    // convidado (decisão #2), sem apagar as contribuições dele.
    await _reconcileSharedEnvironments(db, remoteIds);
  }

  Future<bool> _pushEnvironments(SoproDatabase db, AuthSession s) async {
    final dao = db.environmentsDao;
    // ownerId != null = cópia read-only do dono → o convidado nunca a reenvia
    // (RLS do servidor rejeitaria o UPDATE do id alheio e quebraria o lote).
    final rows = (await dao.allForSync())
        .where((r) => r.updatedAt != null && r.ownerId == null);
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
    if (payload.isEmpty) return true;
    return _upsert('environments', payload);
  }

  Future<void> _syncTriggers(SoproDatabase db, AuthSession s) async {
    await _pullTriggers(db, s);
    await _pushTriggers(db, s);
  }

  Future<void> _pullTriggers(SoproDatabase db, AuthSession s) async {
    final dao = db.triggersDao;
    final remote = await _get('triggers');
    if (remote == null) return;
    final localById = {for (final r in await dao.allForSync()) r.id: r};
    final remoteIds = <String>{};
    for (final m in remote) {
      final id = m['id'] as String;
      remoteIds.add(id);
      final rUpd = _parseTs(m['updated_at']);
      final local = localById[id];
      if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
        final remoteOwner = m['user_id'] as String?;
        final ownerId =
            (remoteOwner != null && remoteOwner != s.userId) ? remoteOwner : null;
        await dao.applyRemote(TriggersCompanion(
          id: Value(id),
          environmentId: Value(m['environment_id'] as String),
          title: Value(m['title'] as String? ?? ''),
          content: Value(m['content'] as String? ?? ''),
          isActive: Value(m['is_active'] as bool? ?? true),
          createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
          updatedAt: Value(rUpd),
          deletedAt: Value(_parseTs(m['deleted_at'])),
          ownerId: Value(ownerId),
        ));
      }
    }
    // Gatilho read-only do dono (ownerId != null) que sumiu do PULL = opção
    // "compartilhar gatilhos" desligada ou share revogado → remove localmente.
    await _reconcileSharedTriggers(db, remoteIds);
  }

  Future<bool> _pushTriggers(SoproDatabase db, AuthSession s) async {
    final dao = db.triggersDao;
    // Só os gatilhos próprios (ownerId null) sobem — nunca a cópia do dono.
    final rows = (await dao.allForSync())
        .where((r) => r.updatedAt != null && r.ownerId == null);
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
    if (payload.isEmpty) return true;
    return _upsert('triggers', payload);
  }

  Future<void> _syncReminders(SoproDatabase db, AuthSession s) async {
    await _pullReminders(db);
    await _pushReminders(db, s);
  }

  Future<void> _pullReminders(SoproDatabase db) async {
    final dao = db.scheduledRemindersDao;
    final remote = await _get('scheduled_reminders');
    if (remote == null) return;
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

  Future<bool> _pushReminders(SoproDatabase db, AuthSession s) async {
    final dao = db.scheduledRemindersDao;
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
    if (payload.isEmpty) return true;
    return _upsert('scheduled_reminders', payload);
  }

  Future<void> _syncShopping(SoproDatabase db, AuthSession s) async {
    await _pullShopping(db, s);
    await _pushShopping(db, s);
  }

  Future<void> _pullShopping(SoproDatabase db, AuthSession s) async {
    final dao = db.shoppingListItemsDao;
    final remote = await _get('shopping_list_items');
    if (remote == null) return;
    final localById = {for (final r in await dao.allForSync()) r.id: r};
    for (final m in remote) {
      final id = m['id'] as String;
      final rUpd = _parseTs(m['updated_at']);
      final local = localById[id];
      if (_remoteWins(rUpd, local?.updatedAt, isNew: local == null)) {
        // ownerId marca o autor do item (usado só ao revogar, p/ separar os meus).
        final remoteOwner = m['user_id'] as String?;
        final ownerId =
            (remoteOwner != null && remoteOwner != s.userId) ? remoteOwner : null;
        await dao.applyRemote(ShoppingListItemsCompanion(
          id: Value(id),
          environmentId: Value(m['environment_id'] as String),
          name: Value(m['name'] as String? ?? ''),
          isChecked: Value(m['is_checked'] as bool? ?? false),
          createdAt: Value(_parseTs(m['created_at']) ?? DateTime.now()),
          updatedAt: Value(rUpd),
          deletedAt: Value(_parseTs(m['deleted_at'])),
          ownerId: Value(ownerId),
        ));
      }
    }
  }

  // Lista de compras é sempre colaborativa: sobe TODOS os itens (o trigger
  // BEFORE UPDATE no servidor preserva a autoria). ownerId não filtra aqui.
  Future<bool> _pushShopping(SoproDatabase db, AuthSession s) async {
    final dao = db.shoppingListItemsDao;
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
    if (payload.isEmpty) return true;
    return _upsert('shopping_list_items', payload);
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

  // ── Reconciliação de compartilhamento (Fase 3) ──────────────────────────────

  // Ambientes que eram cópia read-only (ownerId != null) e sumiram do PULL têm o
  // compartilhamento revogado/removido. Decisão #2: não apagar as contribuições do
  // convidado — o ambiente vira uma cópia PRÓPRIA e independente dele.
  Future<void> _reconcileSharedEnvironments(
      SoproDatabase db, Set<String> remoteIds) async {
    final locals = await db.environmentsDao.allForSync();
    for (final e in locals) {
      if (e.ownerId != null && e.deletedAt == null && !remoteIds.contains(e.id)) {
        await _detachSharedEnvironment(db, e);
      }
    }
  }

  // Re-chaveia o ambiente compartilhado revogado para um id NOVO, próprio do
  // convidado. Um id novo evita colisão de RLS no PUSH (o id antigo pertence ao
  // dono no servidor). Migra as contribuições do convidado (gatilhos e itens que
  // ELE criou, ownerId null) e descarta os artefatos read-only do dono. Troca o
  // geofence registrado — o motor nativo dispara igual, pois lê qualquer ambiente
  // local independentemente de dono.
  Future<void> _detachSharedEnvironment(SoproDatabase db, Environment old) async {
    const uuid = Uuid();
    final newId = uuid.v4();
    final now = DateTime.now();

    // 1. Novo ambiente próprio (ownerId null → sobe no PUSH sob a conta do convidado).
    await db.into(db.environments).insert(EnvironmentsCompanion.insert(
          id: newId,
          name: old.name,
          latitude: old.latitude,
          longitude: old.longitude,
          radiusMeters: old.radiusMeters,
          createdAt: old.createdAt,
          isMarket: Value(old.isMarket),
          updatedAt: Value(now),
        ));

    // 2a. Gatilhos PRÓPRIOS do convidado: re-parenta mantendo o mesmo id (o
    //     convidado é dono da linha no servidor → RLS permite o UPDATE do env).
    await (db.update(db.triggers)
          ..where((t) =>
              t.environmentId.equals(old.id) &
              t.ownerId.isNull() &
              t.deletedAt.isNull()))
        .write(TriggersCompanion(
            environmentId: Value(newId), updatedAt: Value(now)));

    // 2b. Itens de compra PRÓPRIOS do convidado: re-cria com id NOVO. A RLS de
    //     shopping valida por pertencer ao ambiente; como o ambiente antigo já foi
    //     revogado, um UPDATE do id existente seria bloqueado — INSERT novo no
    //     ambiente próprio passa. As linhas antigas são descartadas no passo 3.
    final myItems = await (db.select(db.shoppingListItems)
          ..where((i) =>
              i.environmentId.equals(old.id) &
              i.ownerId.isNull() &
              i.deletedAt.isNull()))
        .get();
    for (final it in myItems) {
      await db.into(db.shoppingListItems).insert(ShoppingListItemsCompanion.insert(
            id: uuid.v4(),
            environmentId: newId,
            name: it.name,
            isChecked: Value(it.isChecked),
            createdAt: it.createdAt,
            updatedAt: Value(now),
          ));
    }

    // 3. Descarta os artefatos ligados ao ambiente compartilhado antigo: itens
    //    (do dono + as cópias antigas dos meus, já recriadas) e gatilhos read-only
    //    do dono; por fim o ambiente. Hard delete local — não vira tombstone nem
    //    sobe no PUSH (não são do convidado).
    await (db.delete(db.shoppingListItems)
          ..where((i) => i.environmentId.equals(old.id)))
        .go();
    await (db.delete(db.triggers)
          ..where((t) => t.environmentId.equals(old.id) & t.ownerId.isNotNull()))
        .go();
    await (db.delete(db.environments)..where((e) => e.id.equals(old.id))).go();

    // 4. Geofence: remove o id antigo e registra o novo.
    try {
      await _geofence.removeGeofence(old.id);
      await _geofence.addGeofence(
        id: newId,
        lat: old.latitude,
        lng: old.longitude,
        radiusMeters: old.radiusMeters,
        name: old.name,
      );
    } catch (_) {
      // MethodChannel indisponível (ex.: sync sem engine de UI) — ignora; o
      // BootReceiver/registro do Home re-registra o geofence do novo id depois.
    }

    Logger.info('share_revoked_detached',
        feature: 'sync',
        action: 'detach',
        payload: {'old_env': old.id, 'new_env': newId});
  }

  // Gatilhos read-only do dono (ownerId != null) que sumiram do PULL → remoção
  // local (hard delete). Cobre "compartilhar gatilhos" desligado num ambiente que
  // continua compartilhado. Nunca toca os gatilhos próprios do convidado (ownerId null).
  Future<void> _reconcileSharedTriggers(
      SoproDatabase db, Set<String> remoteIds) async {
    final locals = await db.triggersDao.allForSync();
    for (final t in locals) {
      if (t.ownerId != null && !remoteIds.contains(t.id)) {
        await (db.delete(db.triggers)..where((x) => x.id.equals(t.id))).go();
      }
    }
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
  // Retorna true em 2xx; false em erro de rede/HTTP (usado pelo flush do logout).
  Future<bool> _upsert(String table, List<Map<String, dynamic>> rows) async {
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
        return false;
      }
      return true;
    } catch (_) {
      // offline/erro no PUSH — silencioso; a próxima rodada tenta de novo.
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // ── Timestamps (timestamptz ISO-8601) ───────────────────────────────────────
  String _fmt(DateTime dt) => dt.toUtc().toIso8601String();
  DateTime? _parseTs(Object? v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v)?.toLocal() : null;
}
