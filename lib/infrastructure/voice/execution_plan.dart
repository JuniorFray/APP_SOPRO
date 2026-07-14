// ExecutionPlan — modelo reutilizável de um plano de ações do assistente de voz.
//
// Objetivo (Fase 2): deixar o Gemini apenas ESTRUTURAR a intenção do usuário como
// uma lista de ações; toda a regra de negócio (GPS, geocoding, persistência,
// confirmação) é executada pelo app via VoiceActionExecutor. Este arquivo contém
// somente modelos de dados puros (sem dependências de Flutter/Riverpod), o que os
// torna reutilizáveis e testáveis isoladamente.
//
// Fluxo: Gemini → List<VoiceAction> → ExecutionPlan → VoiceActionExecutor.run().

// Tipos de ação suportados pelo executor. O nome no wire (JSON do Gemini) é o
// snake_case correspondente — ver [fromWire].
enum VoiceActionType {
  createEnvironment,
  deleteEnvironment,
  deleteAllEnvironments,
  createTrigger,
  deleteTrigger,
  deleteAllTriggers,
  updateTrigger,
  updateEnvironment,
  // Ação não reconhecida — executor a marca como falha sem abortar o plano.
  unknown,
}

// Status de cada ação ao longo da execução sequencial.
enum ActionStatus { pending, running, done, failed }

// Uma ação isolada do plano. Mutável: o executor atualiza status/erro/resultado
// conforme processa. [params] carrega os campos específicos do tipo (ex.: name,
// environment, title, content, radius) exatamente como o Gemini os estruturou.
class VoiceAction {
  final VoiceActionType type;
  final Map<String, dynamic> params;
  ActionStatus status;
  String? error;
  String? result;

  VoiceAction({
    required this.type,
    this.params = const {},
    this.status = ActionStatus.pending,
    this.error,
    this.result,
  });

  // Ações que apagam dados — exigem confirmação por voz no nível do plano (Fase 1).
  bool get isDestructive =>
      type == VoiceActionType.deleteEnvironment ||
      type == VoiceActionType.deleteAllEnvironments ||
      type == VoiceActionType.deleteTrigger ||
      type == VoiceActionType.deleteAllTriggers;

  // Leitura tolerante de um campo de string dentre chaves alternativas.
  // Motivo: o Gemini às vezes usa "name" e às vezes "environment" para o local.
  String? str(List<String> keys) {
    for (final k in keys) {
      final v = params[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  // Converte o "type" textual do JSON do Gemini no enum. Desconhecido → unknown.
  static VoiceActionType fromWire(String? wire) {
    switch (wire) {
      case 'create_environment':      return VoiceActionType.createEnvironment;
      case 'delete_environment':      return VoiceActionType.deleteEnvironment;
      case 'delete_all_environments': return VoiceActionType.deleteAllEnvironments;
      case 'create_trigger':          return VoiceActionType.createTrigger;
      case 'delete_trigger':          return VoiceActionType.deleteTrigger;
      case 'delete_all_triggers':     return VoiceActionType.deleteAllTriggers;
      case 'update_trigger':          return VoiceActionType.updateTrigger;
      case 'update_environment':      return VoiceActionType.updateEnvironment;
      default:                        return VoiceActionType.unknown;
    }
  }

  // Constrói uma ação a partir de um objeto JSON {"type":..., ...params}.
  // Todos os campos além de "type" viram [params] (o executor lê o que precisa).
  static VoiceAction fromJson(Map<String, dynamic> json) {
    final type = fromWire(json['type'] as String?);
    final params = Map<String, dynamic>.from(json)..remove('type');
    return VoiceAction(type: type, params: params);
  }
}

// Sequência ordenada de ações a executar. Imutável na estrutura (a lista em si),
// mas cada VoiceAction interna é atualizada pelo executor.
class ExecutionPlan {
  final List<VoiceAction> actions;
  const ExecutionPlan(this.actions);

  bool get isEmpty => actions.isEmpty;
  bool get isNotEmpty => actions.isNotEmpty;

  // True se qualquer ação apaga dados → dispara confirmação única por voz.
  bool get hasDestructive => actions.any((a) => a.isDestructive);

  // Precisa de GPS? (criar ambiente resolve a localização atual).
  bool get needsLocation =>
      actions.any((a) => a.type == VoiceActionType.createEnvironment);

  // Constrói o plano a partir da lista "actions" do JSON do Gemini.
  static ExecutionPlan fromJsonList(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const ExecutionPlan([]);
    final actions = <VoiceAction>[];
    for (final item in raw) {
      if (item is Map) {
        actions.add(VoiceAction.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return ExecutionPlan(actions);
  }
}

// Resumo do resultado da execução — usado para a resposta natural e os logs.
class ExecutionSummary {
  final ExecutionPlan plan;
  const ExecutionSummary(this.plan);

  int get total  => plan.actions.length;
  int get ok     => plan.actions.where((a) => a.status == ActionStatus.done).length;
  int get failed => plan.actions.where((a) => a.status == ActionStatus.failed).length;
  bool get allOk         => failed == 0 && ok > 0;
  bool get partialFailure => failed > 0 && ok > 0;
}
