import 'package:flutter_riverpod/flutter_riverpod.dart';

// ConversationContext — memória temporária de conversa do assistente de voz.
//
// Objetivo (Fase 2): permitir diálogo natural sem re-perguntar o óbvio. Ex.:
//   Usuário: "Amanhã vou ao médico."   → cria/foca ambiente "Médico"
//   Usuário: "Também preciso pegar o exame." → anexa ao "Médico" sem perguntar.
//
// Decisões:
//   - SOMENTE RAM. Nunca persiste em banco (privacidade + simplicidade).
//   - TTL curto: após [_ttl] sem uso, o contexto expira e é limpo, evitando que
//     uma fala nova herde um contexto velho e irrelevante.
//   - Sem timers: a expiração é verificada sob demanda (isExpired) na próxima
//     interação — zero custo de CPU/bateria em segundo plano.
//   - Injetado no prompt do Gemini via [promptSummary] para o modelo resolver
//     referências implícitas ("o exame" → ambiente Médico).

// Estado explícito da conversa (substitui flags espalhadas na lógica de voz).
// O estado VISUAL do botão continua em _FabState; este enum descreve a CONVERSA.
enum ConversationState {
  idle,                 // sem conversa ativa
  listening,            // capturando áudio do usuário
  thinking,             // aguardando/parseando resposta do Gemini
  executing,            // rodando o ExecutionPlan
  awaitingInformation,  // faltou um dado; assistente perguntou e espera resposta
  awaitingConfirmation, // operação destrutiva aguardando "sim/não"
  completed,            // interação concluída com sucesso
  cancelled,            // usuário cancelou ou não confirmou
}

class ConversationContext {
  // Janela de validade do contexto. Curta o suficiente para não "vazar" entre
  // conversas distintas; longa o suficiente para um diálogo encadeado natural.
  static const Duration _ttl = Duration(minutes: 2);

  ConversationState state = ConversationState.idle;

  // Últimos elementos relevantes para resolver referências implícitas.
  String? lastEnvironment; // último ambiente mencionado/criado
  String? lastTrigger;     // último lembrete mencionado/criado
  String? lastIntent;      // última intenção principal (diagnóstico)
  String? lastQuestion;    // última pergunta feita pelo assistente (follow-up)

  // Marca de tempo do último toque — base do TTL.
  DateTime _updatedAt = DateTime.now();

  // True se o contexto passou do TTL e deve ser descartado antes de reutilizar.
  bool get isExpired => DateTime.now().difference(_updatedAt) > _ttl;

  // True se não há nada útil guardado (evita injetar contexto vazio no prompt).
  bool get isEmpty =>
      lastEnvironment == null &&
      lastTrigger == null &&
      lastIntent == null &&
      lastQuestion == null;

  // Renova o TTL. Chamado sempre que o contexto é lido/escrito de forma relevante.
  void touch() => _updatedAt = DateTime.now();

  // Aplica os "context_updates" que o próprio Gemini sugere na resposta.
  // Só sobrescreve quando vem valor não vazio — nunca apaga por omissão.
  void applyUpdates(Map<String, dynamic>? updates) {
    if (updates == null) return;
    final env = updates['last_environment'];
    final trg = updates['last_trigger'];
    final itt = updates['last_intent'];
    if (env is String && env.trim().isNotEmpty) lastEnvironment = env.trim();
    if (trg is String && trg.trim().isNotEmpty) lastTrigger = trg.trim();
    if (itt is String && itt.trim().isNotEmpty) lastIntent = itt.trim();
    touch();
  }

  // Zera tudo (contexto expirado, conversa concluída/cancelada, ou reset manual).
  void clear() {
    state = ConversationState.idle;
    lastEnvironment = null;
    lastTrigger = null;
    lastIntent = null;
    lastQuestion = null;
    touch();
  }

  // Trecho de contexto injetado no prompt do Gemini. Retorna '' quando não há
  // contexto útil ou está expirado — nesse caso o modelo age sem contexto extra.
  String promptSummary() {
    if (isExpired || isEmpty) return '';
    final buf = StringBuffer('Contexto recente da conversa (use para resolver '
        'referencias implicitas; NAO repita perguntas ja respondidas):');
    if (lastEnvironment != null) buf.write('\n- ultimo ambiente: $lastEnvironment');
    if (lastTrigger != null)     buf.write('\n- ultimo lembrete: $lastTrigger');
    if (lastQuestion != null)    buf.write('\n- ultima pergunta do assistente: $lastQuestion');
    return buf.toString();
  }
}

// Provider singleton — mantém o contexto vivo enquanto a Home existe (RAM).
// O TTL interno garante que um contexto ocioso não seja reutilizado indevidamente.
final conversationContextProvider =
    Provider<ConversationContext>((ref) => ConversationContext());
