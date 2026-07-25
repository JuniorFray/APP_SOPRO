// buildActionHandlers — registro que instancia as Skills e monta o mapa
// VoiceActionType → ActionHandler consumido pelo VoiceActionExecutor.
//
// Estágio 3 (comportamento-preservado): a regra de negócio de cada handler
// mudou de lugar — saiu das closures deste arquivo e virou uma classe Skill
// própria em ../skills/voice_skills.dart. Aqui só se monta o [SkillContext]
// (dependências resolvidas via Riverpod uma vez por plano) e liga cada tipo de
// ação ao call() da Skill correspondente. Assinatura e contrato inalterados.
//
// A ÚNICA dependência de UI (escolher entre vários mercados no add_shopping_item)
// continua injetada via [pickMarket], porque o widget de escolha (_EnvPickerSheet)
// é privado da Home. Callers sem picker (null) apenas degradam esse caso raro.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/database_provider.dart';
import '../../presentation/providers/location_providers.dart';
import '../../presentation/providers/voice_providers.dart';
import '../skills/base_skill.dart';
import '../skills/voice_skills.dart';
import 'execution_plan.dart';
import 'voice_action_executor.dart';

// Reexporta MarketPicker (agora definido junto do SkillContext) para não quebrar
// quem importa este arquivo pelo tipo do parâmetro pickMarket.
export '../skills/base_skill.dart' show MarketPicker;

// Constrói os handlers do executor ligando cada tipo de ação à Skill real.
// [loc] é o GPS resolvido uma vez para o plano todo.
Map<VoiceActionType, ActionHandler> buildActionHandlers(
  WidgetRef ref,
  BuildContext context, {
  ({double lat, double lng})? loc,
  MarketPicker? pickMarket,
}) {
  // TTS respeitando a preferência do usuário (mesma lógica do _speak da Home).
  Future<void> speak(String text) async {
    if (!ref.read(voiceAudioResponseProvider)) return;
    final rate = ref.read(voiceSpeechRateProvider);
    try {
      await ref.read(voiceServiceProvider).speak(text, rate: rate);
    } catch (_) {}
  }

  // Dependências resolvidas uma vez e compartilhadas por todas as Skills do plano.
  final ctx = SkillContext(
    envRepo:    ref.read(environmentRepositoryProvider),
    trgRepo:    ref.read(triggerRepositoryProvider),
    shopRepo:   ref.read(shoppingListRepositoryProvider),
    remRepo:    ref.read(scheduledReminderRepositoryProvider),
    geofence:   ref.read(nativeGeofenceServiceProvider),
    speak:      speak,
    loc:        loc,
    context:    context,
    pickMarket: pickMarket,
  );

  // Liga cada tipo de ação ao ciclo validate→execute→respond da Skill.
  return {
    VoiceActionType.createEnvironment:     (a) => CreateEnvironmentSkill().call(a, ctx),
    VoiceActionType.createTrigger:         (a) => CreateTriggerSkill().call(a, ctx),
    VoiceActionType.addShoppingItem:       (a) => AddShoppingItemSkill().call(a, ctx),
    VoiceActionType.createReminder:        (a) => CreateReminderSkill().call(a, ctx),
    VoiceActionType.updateTrigger:         (a) => UpdateTriggerSkill().call(a, ctx),
    VoiceActionType.updateEnvironment:     (a) => UpdateEnvironmentSkill().call(a, ctx),
    VoiceActionType.deleteEnvironment:     (a) => DeleteEnvironmentSkill().call(a, ctx),
    VoiceActionType.deleteAllEnvironments: (a) => DeleteAllEnvironmentsSkill().call(a, ctx),
    VoiceActionType.deleteTrigger:         (a) => DeleteTriggerSkill().call(a, ctx),
    VoiceActionType.deleteAllTriggers:     (a) => DeleteAllTriggersSkill().call(a, ctx),
  };
}
