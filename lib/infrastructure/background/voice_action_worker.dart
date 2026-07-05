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
    await AppLogger.init();

    if (taskName != kVoiceActionTask) {
      // Tarefa desconhecida — conclui com sucesso para não retentar indefinidamente
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    final actionJson = prefs.getString(_kPendingKey);

    if (actionJson == null || actionJson.isEmpty) {
      AppLogger.log('voice_action_worker', {'status': 'no_pending_action'});
      return true;
    }

    // Remove antes de processar — evita duplicata se o processo for morto a meio
    await prefs.remove(_kPendingKey);

    Map<String, dynamic> action;
    try {
      action = jsonDecode(actionJson) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.log('voice_action_worker', {'status': 'json_error', 'error': '$e'});
      return true;
    }

    final intent = action['intent'] as String? ?? '';
    final db = SoproDatabase();

    try {
      if (intent == 'create_environment') {
        await _createEnvironment(db, action);
      } else if (intent == 'create_trigger') {
        await _createTrigger(db, action);
      } else {
        AppLogger.log('voice_action_worker', {
          'status': 'unknown_intent',
          'intent': intent,
        });
      }
    } catch (e) {
      AppLogger.log('voice_action_worker', {
        'status': 'error',
        'intent': intent,
        'error': '$e',
      });
    } finally {
      await db.close();
    }

    return true;
  });
}

// Salva ambiente via Drift usando o UUID pré-gerado pelo FloatingVoiceService.
// Usar o mesmo UUID garante que o geofence nativo registrado pela Kotlin aponte
// para o mesmo ID que o ambiente armazenado no banco Dart.
Future<void> _createEnvironment(SoproDatabase db, Map<String, dynamic> a) async {
  // 'id' vem do Kotlin para que geofence e DB compartilhem o mesmo UUID
  final id     = a['id']     as String? ?? const Uuid().v4();
  final name   = a['name']   as String? ?? '';
  final lat    = (a['lat']   as num?)?.toDouble()    ?? 0.0;
  final lon    = (a['lon']   as num?)?.toDouble()    ?? 0.0;
  final radius = (a['radius'] as num?)?.toDouble()   ?? 100.0;

  if (name.isEmpty) {
    AppLogger.log('voice_action_worker', {'status': 'env_name_empty'});
    return;
  }

  final env = EnvironmentEntity(
    id:           id,
    name:         name,
    latitude:     lat,
    longitude:    lon,
    radiusMeters: radius,
    createdAt:    DateTime.now(),
  );

  await EnvironmentRepository(db.environmentsDao).save(env);

  AppLogger.log('voice_action_worker', {
    'status':   'env_saved',
    'env_name': name,
    'id':       id,
  });
}

// Busca o ambiente pelo nome (exact match case-insensitive, depois contains),
// e salva o trigger via Drift.
Future<void> _createTrigger(SoproDatabase db, Map<String, dynamic> a) async {
  final envName = a['env_name'] as String? ?? '';
  final title   = a['title']   as String? ?? '';
  final content = a['content'] as String? ?? '';

  if (envName.isEmpty || title.isEmpty) {
    AppLogger.log('voice_action_worker', {
      'status':   'trigger_missing_fields',
      'env_name': envName,
      'title':    title,
    });
    return;
  }

  final allEnvs = await EnvironmentRepository(db.environmentsDao).getAll();
  final lower   = envName.toLowerCase();

  // 1ª passagem: match exato case-insensitive
  EnvironmentEntity? env;
  for (final e in allEnvs) {
    if (e.name.toLowerCase() == lower) { env = e; break; }
  }
  // 2ª passagem: contains como fallback (mesmo critério do _matchEnv em home_screen)
  if (env == null) {
    for (final e in allEnvs) {
      if (e.name.toLowerCase().contains(lower) ||
          lower.contains(e.name.toLowerCase())) {
        env = e; break;
      }
    }
  }

  if (env == null) {
    AppLogger.log('voice_action_worker', {
      'status':   'env_not_found',
      'env_name': envName,
    });
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

  AppLogger.log('voice_action_worker', {
    'status':   'trigger_saved',
    'env_name': envName,
    'title':    title,
    'id':       trigger.id,
  });
}
