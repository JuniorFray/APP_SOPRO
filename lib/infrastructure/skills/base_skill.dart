import 'package:flutter/material.dart';

import '../../domain/entities/environment_entity.dart';
import '../../domain/repositories/i_environment_repository.dart';
import '../../domain/repositories/i_scheduled_reminder_repository.dart';
import '../../domain/repositories/i_shopping_list_repository.dart';
import '../../domain/repositories/i_trigger_repository.dart';
import '../geofence/native_geofence_service.dart';
import '../voice/execution_plan.dart';

// Base Skill — contrato padrão de todas as Skills de voz do Sopro.
// Formaliza voice_structure_doc/architecture/05-Base-Skill.md: ciclo de vida
// único validate() → execute() → respond(), executável pelo Planner/Executor
// sem tratamento especial.
//
// NOTA de refatoração (Estágio 3, comportamento-preservado): a regra de negócio
// de cada handler foi movida INTEGRALMENTE para execute(), retornando a MESMA
// string de resultado (wire) e lançando as MESMAS exceções de antes. validate()
// e respond() existem como pontos de extensão (validate = no-op; respond =
// identidade). O Behavior Engine (Estágio 6) assumirá respond() depois.

// Como a UI resolve a escolha entre VÁRIOS mercados no add_shopping_item.
// [subtitle] é o item a adicionar; [onPicked] persiste no mercado escolhido.
typedef MarketPicker = void Function(
  String subtitle,
  Future<void> Function(EnvironmentEntity env) onPicked,
);

// Dependências que as Skills usam (repositórios, geofence, GPS, TTS, UI).
// Montado uma vez por plano em buildActionHandlers e injetado em cada execute().
class SkillContext {
  final IEnvironmentRepository envRepo;
  final ITriggerRepository trgRepo;
  final IShoppingListRepository shopRepo;
  final IScheduledReminderRepository remRepo;
  final NativeGeofenceService geofence;

  // TTS respeitando a preferência do usuário (mesma lógica do _speak da Home).
  final Future<void> Function(String text) speak;

  // GPS resolvido uma vez para o plano todo. null em comandos de texto.
  final ({double lat, double lng})? loc;

  // Contexto de UI — usado para context.mounted e para o picker de mercado.
  final BuildContext context;

  // Injeção da escolha de mercado (widget privado da Home). null degrada o caso.
  final MarketPicker? pickMarket;

  const SkillContext({
    required this.envRepo,
    required this.trgRepo,
    required this.shopRepo,
    required this.remRepo,
    required this.geofence,
    required this.speak,
    required this.loc,
    required this.context,
    required this.pickMarket,
  });
}

// Contrato de uma Skill. Cada Skill tem identidade (id/name/description) e o
// ciclo validate → execute → respond do spec 05.
abstract class BaseSkill {
  // Identidade da Skill (usada pelo Plugin System, Estágio 9).
  String get id;
  String get name;
  String get description;

  // validate(): verifica parâmetros/pré-condições. Lança a string de erro
  // (mesmo código de antes) quando inválido. Default: nada a validar — as guard
  // clauses seguem dentro de execute() para preservar a ordem exata dos logs.
  void validate(VoiceAction action, SkillContext ctx) {}

  // execute(): regra de negócio. Retorna a string de resultado (wire) idêntica
  // ao handler original; lança em falha (o Executor isola e segue).
  Future<String> execute(VoiceAction a, SkillContext ctx);

  // respond(): ponto de formatação final. Default identidade — o Behavior
  // Engine (Estágio 6) passará a formatar aqui.
  String respond(String result) => result;

  // Template do ciclo de vida (spec 05): validate → execute → respond.
  // É este método que o registro liga ao ActionHandler do Executor.
  Future<String> call(VoiceAction action, SkillContext ctx) async {
    validate(action, ctx);
    final result = await execute(action, ctx);
    return respond(result);
  }
}
