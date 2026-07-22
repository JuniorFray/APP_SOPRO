// buildActionHandlers — mapa compartilhado VoiceActionType → ActionHandler.
//
// Antes vivia como método privado _buildActionHandlers() de _VoiceFabState
// (home_tab_content.dart). Extraído para cá para ser reutilizado por qualquer
// UI que precise executar um ExecutionPlan do Gemini — hoje o FAB de voz da
// Home E o campo de texto da aba Lembretes. Nenhuma lógica de handler mudou; só
// o local onde o código mora.
//
// A ÚNICA dependência de UI (escolher entre vários mercados no add_shopping_item)
// é injetada via [pickMarket], porque o widget de escolha (_EnvPickerSheet) é
// privado da Home. Callers sem picker (null) apenas degradam esse caso raro.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/strings.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/scheduled_reminder_entity.dart';
import '../../domain/entities/shopping_list_item_entity.dart';
import '../../domain/entities/trigger_entity.dart';
import '../logging/app_logger.dart';
import '../../presentation/providers/database_provider.dart';
import '../../presentation/providers/location_providers.dart';
import '../../presentation/providers/voice_providers.dart';
import 'execution_plan.dart';
import 'voice_action_executor.dart';

// Como a UI deve resolver a escolha entre VÁRIOS mercados no add_shopping_item.
// [subtitle] é o item a adicionar; [onPicked] persiste no mercado escolhido.
typedef MarketPicker = void Function(
  String subtitle,
  Future<void> Function(EnvironmentEntity env) onPicked,
);

// Constrói os handlers do executor ligando cada tipo de ação à regra de negócio
// real (repositórios, GPS, geofence). Handlers lançam exceção em falha — o
// executor isola e continua. [loc] é o GPS resolvido uma vez para o plano todo.
Map<VoiceActionType, ActionHandler> buildActionHandlers(
  WidgetRef ref,
  BuildContext context, {
  ({double lat, double lng})? loc,
  MarketPicker? pickMarket,
}) {
  final envRepo = ref.read(environmentRepositoryProvider);
  final trgRepo = ref.read(triggerRepositoryProvider);
  final shopRepo = ref.read(shoppingListRepositoryProvider);
  final remRepo = ref.read(scheduledReminderRepositoryProvider);
  final geofence = ref.read(nativeGeofenceServiceProvider);

  // TTS respeitando a preferência do usuário (mesma lógica do _speak da Home).
  Future<void> speak(String text) async {
    if (!ref.read(voiceAudioResponseProvider)) return;
    final rate = ref.read(voiceSpeechRateProvider);
    try {
      await ref.read(voiceServiceProvider).speak(text, rate: rate);
    } catch (_) {}
  }

  return {
    // Cria ambiente na localização atual. Reusa se já existir (não duplica).
    VoiceActionType.createEnvironment: (a) async {
      final name = a.str(['name', 'environment']);
      if (name == null) {
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('execution_handler_failed',
            {'action': 'create_environment', 'reason': 'nome_vazio'});
        throw 'nome_vazio';
      }
      final existing = _matchEnv(await envRepo.getAll(), name);
      if (existing != null) {
        // LOG TEMPORARIO CALIBRACAO (Fase 2.1) — ambiente ja existia: reutilizado.
        AppLogger.log('existing_environment_detected',
            {'requested': name, 'matched': existing.name});
        return 'ja_existia';
      }
      // LOG TEMPORARIO CALIBRACAO (Fase 2.1) — ambiente novo sera criado.
      AppLogger.log('new_environment_detected', {'name': name});
      // [loc] só é capturado no início de uma GRAVAÇÃO DE VOZ. Comandos de TEXTO
      // (composer bar) chegam com loc null. Nesse caso, usa o último GPS conhecido
      // (last_known_lat/lon, mantido fresco pelo stream do GeofenceManager) — a
      // mesma fonte do viés de geocoding. Só falha com "sem_gps" se também não
      // houver last_known (0.0/ausente), como último recurso.
      var resolvedLoc = loc;
      var locSource = 'gps_current';
      if (resolvedLoc == null) {
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble('last_known_lat') ?? 0.0;
        final lng = prefs.getDouble('last_known_lon') ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          resolvedLoc = (lat: lat, lng: lng);
          locSource = 'last_known';
        }
      }
      if (resolvedLoc == null) {
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('execution_handler_failed',
            {'action': 'create_environment', 'reason': 'sem_gps'});
        throw 'sem_gps';
      }
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_coordinates_before_creation', {
        'environment': name,
        'latitude':    resolvedLoc.lat,
        'longitude':   resolvedLoc.lng,
        'source':      locSource,
      });
      final env = EnvironmentEntity(
        id:           const Uuid().v4(),
        name:         _capitalize(name),
        latitude:     resolvedLoc.lat,
        longitude:    resolvedLoc.lng,
        radiusMeters: 100,
        createdAt:    DateTime.now(),
        isMarket:     false,
      );
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('environment_creation_coordinates', {
        'environment': env.name,
        'lat':         env.latitude,
        'lng':         env.longitude,
        'source':      locSource,
      });
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_repository_save', {
        'environment': env.name,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
      });
      await envRepo.save(env);
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('environment_saved', {
        'environment': env.name,
        'id':          env.id,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
      });
      // TEMP: remover após auditoria da resolução de localização
      AppLogger.log('geofence_coordinates', {
        'environment': env.name,
        'latitude':    env.latitude,
        'longitude':   env.longitude,
        'radius':      env.radiusMeters,
      });
      await geofence.addSingleGeofence(env);
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('location_resolution_result', {
        'resolved':              true,
        'source':                locSource,
        'used_current_location': locSource == 'gps_current',
      });
      return 'ambiente_criado';
    },

    // Cria lembrete num ambiente (que pode ter sido criado antes no mesmo plano).
    VoiceActionType.createTrigger: (a) async {
      final envName = a.str(['environment', 'name']);
      final title   = a.str(['title', 'trigger_title']);
      if (title == null) {
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('execution_handler_failed',
            {'action': 'create_trigger', 'reason': 'titulo_vazio'});
        throw 'titulo_vazio';
      }
      final env = _matchEnv(await envRepo.getAll(), envName);
      if (env == null) {
        // TEMP: remover após calibração da resolução de localização
        AppLogger.log('execution_handler_failed',
            {'action': 'create_trigger', 'reason': 'ambiente_nao_encontrado'});
        throw 'ambiente_nao_encontrado';
      }
      await trgRepo.save(TriggerEntity(
        id:            const Uuid().v4(),
        environmentId: env.id,
        title:         title,
        content:       a.str(['content']) ?? '',
        isActive:      true,
        createdAt:     DateTime.now(),
      ));
      return 'lembrete_criado';
    },

    // Adiciona um item à lista de compras de um MERCADO (isMarket == true).
    // Resolução do mercado: 0 → avisa e pede para criar; 1 → adiciona direto;
    // N → delega a escolha à UI via [pickMarket] (Home injeta o _EnvPickerSheet).
    VoiceActionType.addShoppingItem: (a) async {
      final itemName = a.str(['item', 'name', 'content', 'title']);
      if (itemName == null) throw 'item_vazio';

      final markets =
          (await envRepo.getAll()).where((e) => e.isMarket).toList();

      // Sem mercado cadastrado: não cria ambiente sozinho aqui.
      if (markets.isEmpty) {
        if (context.mounted) await speak(AppStrings.marketVoiceNoMarket);
        return 'sem_mercado';
      }

      // Exatamente um mercado: adiciona direto.
      if (markets.length == 1) {
        await shopRepo.add(ShoppingListItemEntity(
          id:            '',
          environmentId: markets.first.id,
          name:          _capitalize(itemName),
          isChecked:     false,
          createdAt:     DateTime.now(),
        ));
        return 'item_adicionado';
      }

      // Vários mercados: pergunta qual via callback da UI. Sem picker
      // disponível, degrada silenciosamente (caso raro fora da Home).
      if (context.mounted && pickMarket != null) {
        pickMarket(itemName, (env) async {
          await shopRepo.add(ShoppingListItemEntity(
            id:            '',
            environmentId: env.id,
            name:          _capitalize(itemName),
            isChecked:     false,
            createdAt:     DateTime.now(),
          ));
        });
      }
      return 'aguardando_mercado';
    },

    // Cria um lembrete por TEMPO (data/hora), sem vínculo com localização.
    // upsert() já agenda o alarme nativo (ReminderScheduler) internamente.
    VoiceActionType.createReminder: (a) async {
      final title = a.str(['title']) ?? '';
      final dateStr = a.str(['date']);
      final timeStr = a.str(['time']);
      if (title.isEmpty || dateStr == null || timeStr == null) {
        return 'lembrete_incompleto';
      }
      final scheduledAt = _parseDateTime(dateStr, timeStr);
      if (scheduledAt == null) return 'data_invalida';

      final repeatRule = switch (a.str(['repeat_rule']) ?? 'none') {
        'daily' => ReminderRepeatRule.daily,
        'weekly' => ReminderRepeatRule.weekly,
        _ => ReminderRepeatRule.none,
      };
      final daysStr = a.str(['repeat_days_of_week']) ?? '';
      final days = daysStr.isEmpty
          ? <int>[]
          : daysStr
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toList();

      final alertMode = switch (a.str(['alert_mode']) ?? 'notification') {
        'alarm' => ReminderAlertMode.alarm,
        'both' => ReminderAlertMode.both,
        _ => ReminderAlertMode.notification,
      };

      await remRepo.upsert(ScheduledReminderEntity(
        id: '',
        title: _capitalize(title),
        content: '',
        scheduledAt: scheduledAt,
        repeatRule: repeatRule,
        repeatDaysOfWeek: days,
        isActive: true,
        alertMode: alertMode,
        createdAt: DateTime.now(),
      ));
      return 'lembrete_criado';
    },

    // Atualiza um lembrete existente (título e/ou conteúdo) por match de título.
    VoiceActionType.updateTrigger: (a) async {
      final title = a.str(['title']);
      if (title == null) throw 'titulo_vazio';
      final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
      final triggers = env != null ? await trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
      final lower = title.toLowerCase();
      TriggerEntity? t;
      for (final x in triggers) {
        if (x.title.toLowerCase().contains(lower)) { t = x; break; }
      }
      if (t == null) throw 'lembrete_nao_encontrado';
      await trgRepo.save(TriggerEntity(
        id:            t.id, // mesmo id = upsert (atualiza)
        environmentId: t.environmentId,
        title:         a.str(['new_title']) ?? t.title,
        content:       a.str(['content']) ?? t.content,
        isActive:      t.isActive,
        createdAt:     t.createdAt,
      ));
      return 'lembrete_atualizado';
    },

    // Atualiza um ambiente (por ora, o raio) e re-registra o geofence.
    VoiceActionType.updateEnvironment: (a) async {
      final env = _matchEnv(await envRepo.getAll(), a.str(['name', 'environment']));
      if (env == null) throw 'ambiente_nao_encontrado';
      final radius = (a.params['radius'] as num?)?.toDouble() ?? env.radiusMeters;
      final updated = EnvironmentEntity(
        id:           env.id,
        name:         env.name,
        latitude:     env.latitude,
        longitude:    env.longitude,
        radiusMeters: radius,
        createdAt:    env.createdAt,
        isMarket:     env.isMarket,
      );
      await envRepo.save(updated);
      await geofence.addSingleGeofence(updated);
      return 'ambiente_atualizado';
    },

    // Exclui um ambiente (cascade nos gatilhos) + remove geofence.
    // Sem popup por item: a confirmação foi feita no nível do plano.
    VoiceActionType.deleteEnvironment: (a) async {
      final env = _matchEnv(await envRepo.getAll(), a.str(['environment', 'name']));
      if (env == null) throw 'ambiente_nao_encontrado';
      await envRepo.delete(env.id);
      try { await geofence.removeGeofence(env.id); } catch (_) {}
      return 'ambiente_removido';
    },

    // Exclui TODOS os ambientes + limpa geofences.
    VoiceActionType.deleteAllEnvironments: (a) async {
      final all = await envRepo.getAll();
      for (final env in all) { await envRepo.delete(env.id); }
      try { await geofence.clearGeofences(); } catch (_) {}
      return 'todos_ambientes_removidos:${all.length}';
    },

    // Remove um lembrete por match de título no ambiente informado.
    VoiceActionType.deleteTrigger: (a) async {
      final title = a.str(['title']);
      if (title == null) throw 'titulo_vazio';
      final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
      final triggers = env != null ? await trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
      final lower = title.toLowerCase();
      TriggerEntity? t;
      for (final x in triggers) {
        if (x.title.toLowerCase().contains(lower)) { t = x; break; }
      }
      if (t == null) throw 'lembrete_nao_encontrado';
      await trgRepo.delete(t.id);
      return 'lembrete_removido';
    },

    // Remove todos os lembretes de um ambiente.
    VoiceActionType.deleteAllTriggers: (a) async {
      final env = _matchEnv(await envRepo.getAll(), a.str(['environment']));
      if (env == null) throw 'ambiente_nao_encontrado';
      final triggers = await trgRepo.getByEnvironment(env.id);
      for (final t in triggers) { await trgRepo.delete(t.id); }
      return 'lembretes_removidos:${triggers.length}';
    },
  };
}

// ── Helpers puros (cópias das versões da Home; sem estado, seguras de duplicar) ──

// Busca ambiente por nome: igualdade exata (caixa/espaços normalizados) OU
// similaridade > 95% (cobre acento/erro de digitação). Nunca por prefixo.
EnvironmentEntity? _matchEnv(List<EnvironmentEntity> envs, String? query) {
  if (query == null || query.trim().isEmpty) return null;
  final q = _normEnvName(query);
  final exact = envs.where((e) => _normEnvName(e.name) == q).firstOrNull;
  if (exact != null) return exact;
  for (final e in envs) {
    if (_nameSimilarity(_normEnvName(e.name), q) > 0.95) return e;
  }
  return null;
}

String _normEnvName(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

double _nameSimilarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1.0 - _levenshtein(a, b) / maxLen;
}

int _levenshtein(String a, String b) {
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

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// Converte date "AAAA-MM-DD" + time "HH:mm" (do Gemini) num DateTime local.
// Retorna null se o formato for inválido — o handler trata como 'data_invalida'.
DateTime? _parseDateTime(String date, String time) {
  try {
    final d = date.split('-').map(int.parse).toList();
    final t = time.split(':').map(int.parse).toList();
    return DateTime(d[0], d[1], d[2], t[0], t[1]);
  } catch (_) {
    return null;
  }
}
