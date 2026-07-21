// WorkManager callback dispatcher — persiste ações do botão flutuante via Drift.
//
// Executado em isolate de background pelo BackgroundWorker do plugin workmanager.
// MethodChannels NÃO funcionam aqui: usa apenas Drift, SharedPreferences e dart:io.
//
// Fluxo:
//   1. FloatingVoiceService (Kotlin) grava JSON em SharedPreferences e agenda WorkManager.
//   2. Este dispatcher lê o JSON, abre SoproDatabase, salva via repositórios Drift.
//   3. O geofence nativo já foi registrado pelo FloatingVoiceService — não é responsabilidade deste isolate.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/database/sopro_database.dart';
import '../../data/repositories/environment_repository.dart';
import '../../data/repositories/trigger_repository.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/trigger_entity.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../infrastructure/logging/core/correlation_manager.dart';
import '../../infrastructure/logging/core/logger.dart';

// Nome da tarefa — deve coincidir com o valor passado pelo FloatingVoiceService.
const kVoiceActionTask = 'voice_action';

// Chave lida pelo worker em Dart via SharedPreferences.getString('voice_pending_action').
// O plugin Flutter adiciona 'flutter.' automaticamente, então Kotlin deve gravar
// como 'flutter.voice_pending_action' no arquivo 'FlutterSharedPreferences'.
const _kPendingKey = 'voice_pending_action';

// Entry-point do WorkManager — anotação obrigatória para não ser tree-shaken.
// Registrado em main.dart via Workmanager().initialize(callbackDispatcher).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Garante que plugins de plataforma (path_provider, shared_preferences)
    // estejam disponíveis neste isolate antes de qualquer chamada.
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.init(); // necessário neste isolate para inicializar SessionManager

    if (taskName != kVoiceActionTask) {
      return true;
    }

    final correlationId = CorrelationManager.beginOperation('voice_worker');
    final prefs = await SharedPreferences.getInstance();
    final actionJson = prefs.getString(_kPendingKey);

    if (actionJson == null || actionJson.isEmpty) {
      Logger.debug('voice_action_worker', payload: {'status': 'no_pending_action'},
          feature: 'background', action: 'check', correlationId: correlationId);
      CorrelationManager.endOperation('voice_worker');
      return true;
    }

    // Remove antes de processar — evita duplicata se o processo for morto a meio
    await prefs.remove(_kPendingKey);

    Map<String, dynamic> action;
    try {
      action = jsonDecode(actionJson) as Map<String, dynamic>;
    } catch (e, st) {
      Logger.error('voice_action_worker', payload: {'status': 'json_error'},
          exception: e, stackTrace: st,
          feature: 'background', action: 'json_parse', correlationId: correlationId);
      CorrelationManager.endOperation('voice_worker');
      return true;
    }

    final intent = action['intent'] as String? ?? '';
    final db = SoproDatabase();

    try {
      if (intent == 'create_environment') {
        await _createEnvironment(db, action, correlationId);
      } else if (intent == 'create_trigger') {
        await _createTrigger(db, action, correlationId);
      } else {
        Logger.warn('voice_action_worker', payload: {'status': 'unknown_intent', 'intent': intent},
            feature: 'background', action: 'dispatch', correlationId: correlationId);
      }
    } catch (e, st) {
      Logger.error('voice_action_worker', payload: {'status': 'error', 'intent': intent},
          exception: e, stackTrace: st,
          feature: 'background', action: intent, correlationId: correlationId);
    } finally {
      await db.close();
      CorrelationManager.endOperation('voice_worker');
    }

    return true;
  });
}

// Salva ambiente via Drift usando o UUID pré-gerado pelo FloatingVoiceService.
// Usar o mesmo UUID garante que o geofence nativo registrado pela Kotlin aponte
// para o mesmo ID que o ambiente armazenado no banco Dart.
Future<void> _createEnvironment(
    SoproDatabase db, Map<String, dynamic> a, String correlationId) async {
  // 'id' vem do Kotlin para que geofence e DB compartilhem o mesmo UUID
  final id     = a['id']     as String? ?? const Uuid().v4();
  final name   = a['name']   as String? ?? '';
  final lat    = (a['lat']   as num?)?.toDouble()    ?? 0.0;
  final lon    = (a['lon']   as num?)?.toDouble()    ?? 0.0;
  final radius = (a['radius'] as num?)?.toDouble()   ?? 100.0;

  if (name.isEmpty) {
    Logger.warn('voice_action_worker', payload: {'status': 'env_name_empty'},
        feature: 'background', action: 'create_environment', correlationId: correlationId);
    return;
  }

  final env = EnvironmentEntity(
    id:           id,
    name:         name,
    latitude:     lat,
    longitude:    lon,
    radiusMeters: radius,
    createdAt:    DateTime.now(),
    isMarket:     false,
  );

  await EnvironmentRepository(db.environmentsDao).save(env);

  Logger.info('voice_action_worker', payload: {
    'status':   'env_saved',
    'env_name': name,
    'id':       id,
  }, feature: 'background', action: 'create_environment', correlationId: correlationId);
}

// Busca o ambiente pelo nome (exact match case-insensitive, depois contains),
// e salva o trigger via Drift.
Future<void> _createTrigger(
    SoproDatabase db, Map<String, dynamic> a, String correlationId) async {
  final envName = a['env_name'] as String? ?? '';
  final title   = a['title']   as String? ?? '';
  final content = a['content'] as String? ?? '';

  if (envName.isEmpty || title.isEmpty) {
    Logger.warn('voice_action_worker', payload: {
      'status':   'trigger_missing_fields',
      'env_name': envName,
      'title':    title,
    }, feature: 'background', action: 'create_trigger', correlationId: correlationId);
    return;
  }

  final allEnvs = await EnvironmentRepository(db.environmentsDao).getAll();
  // BUG 1 — normaliza (minúsculas + espaços) para comparar nomes com precisão.
  final q = _normEnvName(envName);

  // 1ª passagem: igualdade exata (caixa/espaços normalizados)
  EnvironmentEntity? env;
  for (final e in allEnvs) {
    if (_normEnvName(e.name) == q) { env = e; break; }
  }
  // 2ª passagem: BUG 1 — similaridade > 95% (nunca contains). "Casa" ≠ "Casa da mãe".
  // Mesmo critério do _matchEnv em home_screen.
  if (env == null) {
    for (final e in allEnvs) {
      if (_envNameSimilarity(_normEnvName(e.name), q) > 0.95) { env = e; break; }
    }
  }

  if (env == null) {
    Logger.warn('voice_action_worker', payload: {
      'status':   'env_not_found',
      'env_name': envName,
    }, feature: 'background', action: 'create_trigger', correlationId: correlationId);
    return;
  }

  final trigger = TriggerEntity(
    id:            const Uuid().v4(),
    environmentId: env.id,
    title:         title,
    content:       content,
    isActive:      true,
    createdAt:     DateTime.now(),
  );

  await TriggerRepository(db.triggersDao).save(trigger);

  Logger.info('voice_action_worker', payload: {
    'status':   'trigger_saved',
    'env_name': envName,
    'title':    title,
    'id':       trigger.id,
  }, feature: 'background', action: 'create_trigger', correlationId: correlationId);
}

// Normaliza nome para comparação: minúsculas + colapsa espaços repetidos.
String _normEnvName(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

// BUG 1 — similaridade de nomes (0..1) via Levenshtein: reutiliza um ambiente só
// quando é realmente o mesmo. Sem contains/prefixo.
double _envNameSimilarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1.0 - _levenshteinDistance(a, b) / maxLen;
}

// Distância de edição de Levenshtein (duas linhas, O(n) de memória).
int _levenshteinDistance(String a, String b) {
  final n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev; prev = cur; cur = tmp;
  }
  return prev[n];
}
