import 'execution_plan.dart';

// VoiceActionExecutor — orquestra a execução sequencial de um ExecutionPlan.
//
// Objetivo (Fase 2): separar ORQUESTRAÇÃO (rodar N ações em sequência, tolerar
// falhas, montar resumo) da REGRA DE NEGÓCIO (criar ambiente com GPS, salvar
// gatilho, excluir, etc.). A regra fica em callbacks fornecidos pela camada de UI
// (home_screen), que já tem acesso a repositórios, GPS e geofence. Assim o
// executor não conhece Flutter/Riverpod e é reutilizável/testável.
//
// Contrato dos handlers:
//   - recebem a VoiceAction e retornam uma string curta de resultado (sucesso);
//   - lançam exceção em caso de falha (o executor captura, marca failed e SEGUE).
//   Ação sem handler registrado é marcada como falha, sem abortar o plano.
typedef ActionHandler = Future<String> Function(VoiceAction action);

class VoiceActionExecutor {
  // Mapa tipo-de-ação → handler. Injetado pela UI com a lógica real.
  final Map<VoiceActionType, ActionHandler> handlers;

  const VoiceActionExecutor(this.handlers);

  // Executa cada ação em ordem. Falhas NÃO interrompem as demais (requisito da
  // sprint): cada ação registra seu próprio status/erro/resultado. Ao final,
  // devolve um ExecutionSummary para a resposta natural e os logs.
  Future<ExecutionSummary> run(ExecutionPlan plan) async {
    for (final action in plan.actions) {
      action.status = ActionStatus.running;
      final handler = handlers[action.type];

      // Sem handler (ex.: tipo unknown) → falha isolada, plano continua.
      if (handler == null) {
        action.status = ActionStatus.failed;
        action.error = 'no_handler';
        continue;
      }

      try {
        action.result = await handler(action);
        action.status = ActionStatus.done;
      } catch (e) {
        // Isola a falha: registra e prossegue para a próxima ação.
        action.status = ActionStatus.failed;
        action.error = e.toString();
      }
    }
    return ExecutionSummary(plan);
  }
}
