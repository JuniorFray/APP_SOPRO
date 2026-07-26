import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/scheduled_reminder_entity.dart';
import '../../domain/entities/shopping_list_item_entity.dart';
import '../../domain/entities/trigger_entity.dart';
import '../logging/app_logger.dart';
import '../voice/execution_plan.dart';
import 'base_skill.dart';

// Skills concretas do assistente de voz — uma classe por intenção.
//
// Migração comportamental-preservada (Estágio 3): cada execute() é o corpo do
// handler original de action_handlers_builder.dart, com as dependências vindo de
// [SkillContext] (ctx.*) em vez de variáveis capturadas por closure. Nenhuma
// regra, log ou string de resultado mudou.

// Cria ambiente na localização atual. Reusa se já existir (não duplica).
class CreateEnvironmentSkill extends BaseSkill {
  @override
  String get id => 'create_environment';
  @override
  String get name => 'Criar ambiente';
  @override
  String get description => 'Cria um ambiente no GPS atual (ou reusa existente).';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final name = a.str(['name', 'environment']);
    if (name == null) {
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('execution_handler_failed',
          {'action': 'create_environment', 'reason': 'nome_vazio'});
      throw 'nome_vazio';
    }
    final existing = _matchEnv(await ctx.envRepo.getAll(), name);
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
    var resolvedLoc = ctx.loc;
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
    await ctx.envRepo.save(env);
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
    await ctx.geofence.addSingleGeofence(env);
    // TEMP: remover após calibração da resolução de localização
    AppLogger.log('location_resolution_result', {
      'resolved':              true,
      'source':                locSource,
      'used_current_location': locSource == 'gps_current',
    });
    return 'ambiente_criado';
  }
}

// Cria lembrete num ambiente (que pode ter sido criado antes no mesmo plano).
class CreateTriggerSkill extends BaseSkill {
  @override
  String get id => 'create_trigger';
  @override
  String get name => 'Criar lembrete';
  @override
  String get description => 'Cria um lembrete vinculado a um ambiente.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final envName = a.str(['environment', 'name']);
    final title   = a.str(['title', 'trigger_title']);
    if (title == null) {
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('execution_handler_failed',
          {'action': 'create_trigger', 'reason': 'titulo_vazio'});
      throw 'titulo_vazio';
    }
    final env = _matchEnv(await ctx.envRepo.getAll(), envName);
    if (env == null) {
      // TEMP: remover após calibração da resolução de localização
      AppLogger.log('execution_handler_failed',
          {'action': 'create_trigger', 'reason': 'ambiente_nao_encontrado'});
      throw 'ambiente_nao_encontrado';
    }
    await ctx.trgRepo.save(TriggerEntity(
      id:            const Uuid().v4(),
      environmentId: env.id,
      title:         title,
      content:       a.str(['content']) ?? '',
      isActive:      true,
      createdAt:     DateTime.now(),
    ));
    return 'lembrete_criado';
  }
}

// Adiciona um item à lista de compras de um MERCADO (isMarket == true).
// Resolução do mercado: 0 → avisa e pede para criar; 1 → adiciona direto;
// N → delega a escolha à UI via ctx.pickMarket (Home injeta o _EnvPickerSheet).
class AddShoppingItemSkill extends BaseSkill {
  @override
  String get id => 'add_shopping_item';
  @override
  String get name => 'Adicionar item à lista';
  @override
  String get description => 'Adiciona um item à lista de compras de um mercado.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final itemName = a.str(['item', 'name', 'content', 'title']);
    if (itemName == null) throw 'item_vazio';

    final markets =
        (await ctx.envRepo.getAll()).where((e) => e.isMarket).toList();

    // Sem mercado cadastrado: não cria ambiente sozinho aqui.
    if (markets.isEmpty) {
      if (ctx.context.mounted) await ctx.speak(ctx.persona.marketNoMarket);
      return 'sem_mercado';
    }

    // Exatamente um mercado: adiciona direto.
    if (markets.length == 1) {
      await ctx.shopRepo.add(ShoppingListItemEntity(
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
    if (ctx.context.mounted && ctx.pickMarket != null) {
      ctx.pickMarket!(itemName, (env) async {
        await ctx.shopRepo.add(ShoppingListItemEntity(
          id:            '',
          environmentId: env.id,
          name:          _capitalize(itemName),
          isChecked:     false,
          createdAt:     DateTime.now(),
        ));
      });
    }
    return 'aguardando_mercado';
  }
}

// Cria um lembrete por TEMPO (data/hora), sem vínculo com localização.
// upsert() já agenda o alarme nativo (ReminderScheduler) internamente.
class CreateReminderSkill extends BaseSkill {
  @override
  String get id => 'create_reminder';
  @override
  String get name => 'Criar lembrete por hora';
  @override
  String get description => 'Cria um lembrete por data/hora, sem localização.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
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

    await ctx.remRepo.upsert(ScheduledReminderEntity(
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
  }
}

// Atualiza um lembrete existente (título e/ou conteúdo) por match de título.
class UpdateTriggerSkill extends BaseSkill {
  @override
  String get id => 'update_trigger';
  @override
  String get name => 'Atualizar lembrete';
  @override
  String get description => 'Atualiza título/conteúdo de um lembrete existente.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final title = a.str(['title']);
    if (title == null) throw 'titulo_vazio';
    final env = _matchEnv(await ctx.envRepo.getAll(), a.str(['environment']));
    final triggers = env != null ? await ctx.trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
    final lower = title.toLowerCase();
    TriggerEntity? t;
    for (final x in triggers) {
      if (x.title.toLowerCase().contains(lower)) { t = x; break; }
    }
    if (t == null) throw 'lembrete_nao_encontrado';
    await ctx.trgRepo.save(TriggerEntity(
      id:            t.id, // mesmo id = upsert (atualiza)
      environmentId: t.environmentId,
      title:         a.str(['new_title']) ?? t.title,
      content:       a.str(['content']) ?? t.content,
      isActive:      t.isActive,
      createdAt:     t.createdAt,
    ));
    return 'lembrete_atualizado';
  }
}

// Atualiza um ambiente (por ora, o raio) e re-registra o geofence.
class UpdateEnvironmentSkill extends BaseSkill {
  @override
  String get id => 'update_environment';
  @override
  String get name => 'Atualizar ambiente';
  @override
  String get description => 'Atualiza o raio de um ambiente e re-registra o geofence.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final env = _matchEnv(await ctx.envRepo.getAll(), a.str(['name', 'environment']));
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
      pinImagePath: env.pinImagePath, // preserva a foto do pin ao atualizar raio
    );
    await ctx.envRepo.save(updated);
    await ctx.geofence.addSingleGeofence(updated);
    return 'ambiente_atualizado';
  }
}

// Exclui um ambiente (cascade nos gatilhos) + remove geofence.
// Sem popup por item: a confirmação foi feita no nível do plano.
class DeleteEnvironmentSkill extends BaseSkill {
  @override
  String get id => 'delete_environment';
  @override
  String get name => 'Excluir ambiente';
  @override
  String get description => 'Exclui um ambiente e seus gatilhos, removendo o geofence.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final env = _matchEnv(await ctx.envRepo.getAll(), a.str(['environment', 'name']));
    if (env == null) throw 'ambiente_nao_encontrado';
    await ctx.envRepo.delete(env.id);
    try { await ctx.geofence.removeGeofence(env.id); } catch (_) {}
    return 'ambiente_removido';
  }
}

// Exclui TODOS os ambientes + limpa geofences.
class DeleteAllEnvironmentsSkill extends BaseSkill {
  @override
  String get id => 'delete_all_environments';
  @override
  String get name => 'Excluir todos os ambientes';
  @override
  String get description => 'Exclui todos os ambientes e limpa os geofences.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final all = await ctx.envRepo.getAll();
    for (final env in all) { await ctx.envRepo.delete(env.id); }
    try { await ctx.geofence.clearGeofences(); } catch (_) {}
    return 'todos_ambientes_removidos:${all.length}';
  }
}

// Remove um lembrete por match de título no ambiente informado.
class DeleteTriggerSkill extends BaseSkill {
  @override
  String get id => 'delete_trigger';
  @override
  String get name => 'Excluir lembrete';
  @override
  String get description => 'Remove um lembrete por título dentro de um ambiente.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final title = a.str(['title']);
    if (title == null) throw 'titulo_vazio';
    final env = _matchEnv(await ctx.envRepo.getAll(), a.str(['environment']));
    final triggers = env != null ? await ctx.trgRepo.getByEnvironment(env.id) : <TriggerEntity>[];
    final lower = title.toLowerCase();
    TriggerEntity? t;
    for (final x in triggers) {
      if (x.title.toLowerCase().contains(lower)) { t = x; break; }
    }
    if (t == null) throw 'lembrete_nao_encontrado';
    await ctx.trgRepo.delete(t.id);
    return 'lembrete_removido';
  }
}

// Remove todos os lembretes de um ambiente.
class DeleteAllTriggersSkill extends BaseSkill {
  @override
  String get id => 'delete_all_triggers';
  @override
  String get name => 'Excluir todos os lembretes';
  @override
  String get description => 'Remove todos os lembretes de um ambiente.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final env = _matchEnv(await ctx.envRepo.getAll(), a.str(['environment']));
    if (env == null) throw 'ambiente_nao_encontrado';
    final triggers = await ctx.trgRepo.getByEnvironment(env.id);
    for (final t in triggers) { await ctx.trgRepo.delete(t.id); }
    return 'lembretes_removidos:${triggers.length}';
  }
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
