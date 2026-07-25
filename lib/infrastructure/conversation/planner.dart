import '../voice/execution_plan.dart';
import 'conversation_state.dart';

// Planner — decide o PRÓXIMO PASSO da conversa a partir de um plano do Gemini.
//
// Formaliza voice_structure_doc/architecture/03-Planner.md: nunca executa regra
// de negócio, não interpreta linguagem natural, não acessa banco. Só classifica
// "qual caminho seguir e o que falta" — a execução fica nas Skills e a UI aplica
// os efeitos (confirmar por voz, resolver localização, executar).
//
// Estágio 4 (comportamento-preservado): esta é exatamente a decisão que vivia
// inline em _runAssistantPlan (home_tab_content.dart), agora isolada e pura. O
// que o Gemini retorna não muda; a checagem de "ambiente já existe?" é injetada
// via [environmentExists] para o Planner não tocar em repositórios.

// Passo escolhido pelo Planner para um plano.
enum PlannerStep {
  // Plano vazio → só conversa (o Gemini pediu um dado ou respondeu algo).
  conversational,
  // Há ação destrutiva → confirmar UMA vez por voz antes de executar.
  confirmDestructive,
  // Há UM ambiente novo → resolver localização antes de criar; demais ações
  // ficam pendentes para rodar depois.
  resolveLocation,
  // Pronto para executar direto (resposta natural + execução).
  execute,
}

// Resultado da decisão. Campos extras só são preenchidos no passo resolveLocation.
class PlannerDecision {
  final PlannerStep step;

  // Nome do ambiente novo a resolver (trim aplicado). null fora de resolveLocation.
  final String? environmentName;

  // Ações que rodam DEPOIS da criação do ambiente (gatilhos, etc.).
  final List<VoiceAction> pendingPostEnvActions;

  const PlannerDecision(
    this.step, {
    this.environmentName,
    this.pendingPostEnvActions = const [],
  });
}

class Planner {
  const Planner();

  // Classifica o plano. [environmentExists] responde se um nome de ambiente já
  // existe (o caller liga isso ao seu matcher/repositório) — mantém o Planner
  // puro e desacoplado de banco/UI.
  PlannerDecision decide(
    ExecutionPlan plan, {
    required bool Function(String? name) environmentExists,
  }) {
    // Plano vazio: nada a executar, apenas conversa.
    if (plan.isEmpty) return const PlannerDecision(PlannerStep.conversational);

    // Ação destrutiva presente: confirmação por voz cobre o plano todo.
    if (plan.hasDestructive) {
      return const PlannerDecision(PlannerStep.confirmDestructive);
    }

    // Ambientes NOVOS (create_environment que não casa com um já existente).
    final newCreateEnvs = plan.actions
        .where((a) =>
            a.type == VoiceActionType.createEnvironment &&
            !environmentExists(a.str(['name', 'environment'])))
        .toList();

    // Exatamente um ambiente novo com nome válido → resolve localização primeiro;
    // as demais ações do plano ficam pendentes para depois da criação.
    if (newCreateEnvs.length == 1) {
      final envAction = newCreateEnvs.first;
      final name = envAction.str(['name', 'environment']);
      if (name != null && name.trim().isNotEmpty) {
        final pending =
            plan.actions.where((x) => x != envAction).toList();
        return PlannerDecision(
          PlannerStep.resolveLocation,
          environmentName: name.trim(),
          pendingPostEnvActions: pending,
        );
      }
    }

    // Caso geral: executa direto.
    return const PlannerDecision(PlannerStep.execute);
  }

  // Trata uma resposta a follow-up como CONTINUAÇÃO do comando anterior.
  //
  // Quando o estado é awaitingInformation e há pergunta pendente, a fala nova do
  // usuário sozinha é sinal fraco (o Gemini não sabe qual comando está sendo
  // completado). Este preâmbulo reconstrói o contexto — comando original +
  // pergunta feita + a resposta — para o modelo combinar tudo. Fora desse estado
  // retorna null: comando direto, nada muda (não afeta promptSummary()).
  //
  // [answer] != null → a resposta já é texto (caminho de texto), embutida.
  // [answer] == null → a resposta é o áudio que segue no request (caminho de voz).
  String? continuationPreamble(ConversationContext ctx, {String? answer}) {
    if (ctx.state != ConversationState.awaitingInformation ||
        ctx.lastQuestion == null) {
      return null;
    }
    final original = ctx.lastTranscript ?? '';
    final answerLine = answer != null
        ? "Resposta do usuario a essa pergunta: '$answer'. "
        : 'O audio a seguir e a resposta do usuario a essa pergunta. ';
    return "Comando original do usuario: '$original'. "
        "Voce perguntou: '${ctx.lastQuestion}'. "
        '$answerLine'
        'Combine as informacoes acima para completar a acao original.';
  }
}
