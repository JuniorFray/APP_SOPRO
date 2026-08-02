import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/environment_entity.dart';
import '../../domain/entities/scheduled_reminder_entity.dart';
import '../../domain/entities/shopping_list_item_entity.dart';
import '../../domain/entities/trigger_entity.dart';
import '../logging/app_logger.dart';
import '../voice/execution_plan.dart';
import '../weather/weather_service.dart' show WeatherInfo;
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
      // Confirma o sucesso (paridade com as demais Skills de criação/remoção).
      if (ctx.context.mounted) {
        await ctx.speak(ctx.persona.shoppingItemAdded(_capitalize(itemName)));
      }
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
        // Confirma após a escolha do mercado (mesmo funil de fala das outras Skills).
        if (ctx.context.mounted) {
          await ctx.speak(ctx.persona.shoppingItemAdded(_capitalize(itemName)));
        }
      });
    }
    return 'aguardando_mercado';
  }
}

// Remove um item da lista de compras por match PARCIAL de nome (mesmo padrão do
// DeleteTriggerSkill). Fala a confirmação/erro via persona.
class DeleteShoppingItemSkill extends BaseSkill {
  @override
  String get id => 'delete_shopping_item';
  @override
  String get name => 'Remover item da lista';
  @override
  String get description => 'Remove um item da lista de compras de um mercado.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final itemName = a.str(['item', 'name', 'title']);
    if (itemName == null) throw 'item_vazio';
    final market = await _resolveShoppingMarket(ctx, a.str(['environment']));
    if (market == null) return 'sem_mercado'; // helper já falou o motivo
    final items = await ctx.shopRepo.watchByEnvironment(market.id).first;
    final item = _matchItem(items, itemName);
    if (item == null) {
      if (ctx.context.mounted) {
        await ctx.speak(ctx.persona.shoppingItemNotFound(_capitalize(itemName)));
      }
      return 'item_nao_encontrado';
    }
    await ctx.shopRepo.delete(item.id);
    if (ctx.context.mounted) {
      await ctx.speak(ctx.persona.shoppingItemRemoved(item.name));
    }
    return 'item_removido';
  }
}

// Marca um item como "já peguei" (isChecked = true) por match parcial de nome.
class CheckShoppingItemSkill extends BaseSkill {
  @override
  String get id => 'check_shopping_item';
  @override
  String get name => 'Marcar item como pego';
  @override
  String get description => 'Marca um item da lista como já comprado.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final itemName = a.str(['item', 'name', 'title']);
    if (itemName == null) throw 'item_vazio';
    final market = await _resolveShoppingMarket(ctx, a.str(['environment']));
    if (market == null) return 'sem_mercado';
    final items = await ctx.shopRepo.watchByEnvironment(market.id).first;
    final item = _matchItem(items, itemName);
    if (item == null) {
      if (ctx.context.mounted) {
        await ctx.speak(ctx.persona.shoppingItemNotFound(_capitalize(itemName)));
      }
      return 'item_nao_encontrado';
    }
    await ctx.shopRepo.toggleChecked(item.id, true);
    if (ctx.context.mounted) {
      await ctx.speak(ctx.persona.shoppingItemChecked(item.name));
    }
    return 'item_marcado';
  }
}

// Consulta se um item está na lista; responde sim/não + status (pego ou não).
class QueryShoppingItemSkill extends BaseSkill {
  @override
  String get id => 'query_shopping_item';
  @override
  String get name => 'Consultar item da lista';
  @override
  String get description => 'Responde se um item está na lista de compras.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final itemName = a.str(['item', 'name', 'title']);
    if (itemName == null) throw 'item_vazio';
    final market = await _resolveShoppingMarket(ctx, a.str(['environment']));
    if (market == null) return 'sem_mercado';
    final items = await ctx.shopRepo.watchByEnvironment(market.id).first;
    final item = _matchItem(items, itemName);
    if (ctx.context.mounted) {
      await ctx.speak(item == null
          ? ctx.persona.shoppingItemAbsent(_capitalize(itemName))
          : ctx.persona.shoppingItemPresent(item.name, item.isChecked));
    }
    return item == null ? 'item_ausente' : 'item_presente';
  }
}

// Lista os itens da lista com filtro opcional (all | pending | checked).
class ListShoppingItemsSkill extends BaseSkill {
  @override
  String get id => 'list_shopping_items';
  @override
  String get name => 'Listar itens da lista';
  @override
  String get description =>
      'Lista os itens da lista de compras (todos, pendentes ou pegos).';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final market = await _resolveShoppingMarket(ctx, a.str(['environment']));
    if (market == null) return 'sem_mercado';
    final items = await ctx.shopRepo.watchByEnvironment(market.id).first;
    final filter = (a.str(['filter']) ?? 'all').toLowerCase();
    final names = <String>[];
    final String line;
    switch (filter) {
      case 'pending':
        names.addAll(items.where((i) => !i.isChecked).map((i) => i.name));
        line = ctx.persona.shoppingListPending(names);
      case 'checked':
        names.addAll(items.where((i) => i.isChecked).map((i) => i.name));
        line = ctx.persona.shoppingListChecked(names);
      default:
        names.addAll(items.map((i) => i.name));
        line = ctx.persona.shoppingListAll(names);
    }
    if (ctx.context.mounted) await ctx.speak(line);
    return 'lista_${filter}_${names.length}';
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

    // Default "daily": lembrete sem mencao de repeticao vale todos os dias.
    final repeatRule = switch (a.str(['repeat_rule']) ?? 'daily') {
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
    // BLOCO 1 — update de ENDEREÇO (campo "address") NÃO é resolvido aqui: a Home
    // intercepta antes de executar o plano e conduz o fluxo interativo de local
    // (geocoding + confirmação) retargetado pra UPDATE. Esta Skill trata só o raio;
    // se um "address" chegar até aqui, é ignorado (só o raio é aplicado).
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

// Responde clima/tempo no local atual. Fala o dado direto via persona (o Gemini
// não tem os números). Coords: ctx.loc → fallback last_known_lat/lon (mesma
// fonte das outras Skills). A resposta é falada aqui; o retorno é só o wire.
class WeatherQuerySkill extends BaseSkill {
  @override
  String get id => 'weather_query';
  @override
  String get name => 'Consultar clima';
  @override
  String get description => 'Informa o tempo atual no local do usuário.';

  @override
  Future<String> execute(VoiceAction a, SkillContext ctx) async {
    final place = a.str(['location', 'city', 'place']);
    final scope = (a.str(['scope']) ?? 'now').toLowerCase();

    // Coordenadas do alvo: cidade nomeada (geocoding forward) tem prioridade;
    // senão o GPS do plano; senão o último GPS conhecido (GeofenceManager).
    ({double lat, double lng})? loc;
    String? placeLabel;
    if (place != null) {
      try {
        final results = await ctx.geocoding.search(place);
        if (results.isEmpty) {
          if (ctx.context.mounted) {
            await ctx.speak(ctx.persona.weatherPlaceNotFound);
          }
          return 'lugar_nao_encontrado';
        }
        final g = results.first;
        loc = (lat: g.lat, lng: g.lon);
        placeLabel = g.city.isNotEmpty ? g.city : place;
      } catch (e) {
        AppLogger.log('weather_query_failed',
            {'stage': 'geocode', 'error': e.toString()});
        if (ctx.context.mounted) await ctx.speak(ctx.persona.weatherError);
        return 'erro_clima';
      }
    } else {
      loc = ctx.loc;
      if (loc == null) {
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble('last_known_lat') ?? 0.0;
        final lng = prefs.getDouble('last_known_lon') ?? 0.0;
        if (lat != 0.0 && lng != 0.0) loc = (lat: lat, lng: lng);
      }
      if (loc == null) {
        if (ctx.context.mounted) await ctx.speak(ctx.persona.weatherNoLocation);
        return 'sem_localizacao';
      }
    }

    final hour = DateTime.now().hour;
    try {
      // Previsão dos próximos dias vs. clima agora.
      if (scope == 'week' || scope == 'semana' || scope == 'forecast') {
        // Aviso de espera ANTES da rede — fala não-awaitada roda em paralelo com
        // a busca, sem somar ao tempo da consulta.
        if (ctx.context.mounted) ctx.speak(ctx.persona.weatherChecking);
        final days = await ctx.weather.getForecast(loc.lat, loc.lng);
        if (days.isEmpty) {
          if (ctx.context.mounted) await ctx.speak(ctx.persona.weatherError);
          return 'erro_clima';
        }
        // Molda pra persona: rótulo do dia + min/max + condição em pt-BR (até 4 dias).
        final shaped = days
            .take(4)
            .map((d) => (
                  label: _weekdayLabel(d.date),
                  min: d.tempMin.round(),
                  max: d.tempMax.round(),
                  cond: _condPt(d.condition),
                ))
            .toList();
        if (ctx.context.mounted) {
          await ctx.speak(
              ctx.persona.weatherForecast(shaped, hour: hour, place: placeLabel));
        }
        return 'previsao_ok';
      }

      // Aviso de espera ANTES da rede — fala não-awaitada roda em paralelo com o
      // Future.wait, sem somar ao tempo da consulta.
      if (ctx.context.mounted) ctx.speak(ctx.persona.weatherChecking);
      // Paraleliza as duas chamadas de rede INDEPENDENTES: clima atual (/weather)
      // e chance de chuva (/forecast, HttpClients separados). Antes eram em série
      // (await + await), somando os timeouts; com Future.wait o tempo total é o da
      // MAIS LENTA, não a soma. Ambas são fail-open (devolvem null, nunca lançam),
      // então Future.wait não estoura. Cache/timeout/dados/template inalterados; a
      // heurística qualitativa segue igual, depois destes.
      final results = await Future.wait([
        ctx.weather.getCurrentWeather(loc.lat, loc.lng),
        ctx.weather.getPopSoon(loc.lat, loc.lng),
      ]);
      final info = results[0] as WeatherInfo?;
      final pop = results[1] as int?;
      if (info == null) {
        if (ctx.context.mounted) await ctx.speak(ctx.persona.weatherError);
        return 'erro_clima';
      }

      // Híbrido (Rota A): pergunta ABERTA/qualitativa ("preciso levar casaco?")
      // ganha resposta natural via 2ª chamada Gemini com o dado do clima. Decisão
      // 100% local (heurística) — nunca pede ao Gemini pra decidir. Pergunta
      // DIRETA cai direto no template abaixo (sem custo/latência extra).
      // Fail-open: 2ª chamada falha/sem internet → template estático de sempre.
      if (_isQualitativeWeather(ctx.transcript)) {
        final natural = await _naturalWeatherReply(
            ctx, info, pop, placeLabel, hour);
        if (natural != null) {
          if (ctx.context.mounted) await ctx.speak(natural);
          return 'clima_ok';
        }
      }

      if (ctx.context.mounted) {
        await ctx.speak(ctx.persona.weatherNow(
          temp:        info.tempCelsius,
          description: info.description,
          condition:   info.condition,
          humidity:    info.humidity,
          popPercent:  pop,
          hour:        hour,
          place:       placeLabel,
        ));
      }
      return 'clima_ok';
    } catch (e) {
      AppLogger.log('weather_query_failed', {'error': e.toString()});
      if (ctx.context.mounted) await ctx.speak(ctx.persona.weatherError);
      return 'erro_clima';
    }
  }
}

// Heurística LOCAL (sem custo, sem chamada) que separa pergunta de clima
// ABERTA/qualitativa — quer uma recomendação: "preciso levar casaco?",
// "vale a pena sair?" — de pergunta DIRETA de dado — "que temperatura?",
// "vai chover?". Só a aberta justifica a 2ª chamada Gemini (Rota A). Default:
// direta (mais barato). Acento-insensível: normaliza antes de comparar.
bool _isQualitativeWeather(String phrase) {
  if (phrase.trim().isEmpty) return false;
  final p = _stripAccentsLower(phrase);
  const open = [
    'preciso', 'vou precisar', 'levar', 'vale a pena', 'vale apena',
    'recomenda', 'da pra', 'melhor', 'consigo', 'posso', 'devo',
    'sera que', 'casaco', 'guarda-chuva', 'guarda chuva', 'sombrinha',
    'agasalho', 'roupa',
  ];
  return open.any(p.contains);
}

// Monta o prompt da 2ª chamada (Rota A) com o dado do clima + a fala original e
// pede UMA frase natural respondendo à dúvida. Fail-open é do caller (null cai
// no template). [hour] entra pra resposta considerar o período do dia.
Future<String?> _naturalWeatherReply(SkillContext ctx, WeatherInfo info,
    int? pop, String? place, int hour) async {
  final local = (place == null || place.isEmpty) ? 'no local atual' : 'em $place';
  final chuva = pop == null ? '' : ', chance de chuva $pop%';
  final prompt =
      'Você é o assistente do app Sopro. O usuário fez uma pergunta sobre o '
      'clima e quer uma RECOMENDAÇÃO prática (não só o dado bruto). '
      'Clima agora $local: ${info.tempCelsius.round()}°C, ${info.description}, '
      'umidade ${info.humidity}%$chuva. Hora atual: ${hour}h. '
      'Responda em português do Brasil, tom natural e direto, NO MÁXIMO 1 frase '
      'curta, respondendo à dúvida (ex.: se vale levar casaco/guarda-chuva). '
      'Não liste os dados crus, não use markdown.';
  return ctx.askGemini(prompt, ctx.transcript);
}

// Normaliza para minúsculas removendo acentos comuns pt-BR — usada pela
// heurística de clima pra casar "será"/"sera", "guarda-chuva" etc.
String _stripAccentsLower(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  var r = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i], to[i]);
  }
  return r;
}

// Rótulo do dia da semana em pt-BR para a previsão ("sexta", "sábado"...).
String _weekdayLabel(DateTime d) {
  const names = [
    'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'
  ];
  return names[d.weekday - 1];
}

// Traduz a condição "main" do OpenWeather (inglês) para pt-BR na fala da previsão.
String _condPt(String condition) {
  switch (condition.toLowerCase()) {
    case 'clear':        return 'céu limpo';
    case 'clouds':       return 'nublado';
    case 'rain':         return 'chuva';
    case 'drizzle':      return 'garoa';
    case 'thunderstorm': return 'tempestade';
    case 'snow':         return 'neve';
    case 'mist':
    case 'fog':          return 'neblina';
    case 'haze':         return 'névoa';
    default:             return condition.toLowerCase();
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

// Match PARCIAL de item da lista por nome (mesmo padrão do DeleteTriggerSkill:
// contains, case-insensitive). Primeiro casamento vence. null se nada casar.
ShoppingListItemEntity? _matchItem(
    List<ShoppingListItemEntity> items, String query) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return null;
  for (final it in items) {
    if (it.name.toLowerCase().contains(q)) return it;
  }
  return null;
}

// Resolve QUAL mercado uma ação de lista atinge: [envName] casa um mercado pelo
// nome; senão, o único mercado cadastrado; senão fala o motivo (sem mercado /
// "de qual mercado?") e devolve null. Reusa o padrão de resolução do add.
Future<EnvironmentEntity?> _resolveShoppingMarket(
    SkillContext ctx, String? envName) async {
  final markets = (await ctx.envRepo.getAll()).where((e) => e.isMarket).toList();
  if (markets.isEmpty) {
    if (ctx.context.mounted) await ctx.speak(ctx.persona.marketNoMarket);
    return null;
  }
  if (envName != null) {
    final m = _matchEnv(markets, envName);
    if (m != null) return m;
  }
  if (markets.length == 1) return markets.first;
  if (ctx.context.mounted) await ctx.speak(ctx.persona.shoppingMarketWhich);
  return null;
}

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
