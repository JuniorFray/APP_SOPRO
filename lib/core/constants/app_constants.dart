import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'voice_content.dart';
import 'voice_prompt_assembler.dart';

// Constantes globais do app Sopro.
// Separadas de strings.dart (que contém textos visíveis ao usuário).
class AppConstants {
  AppConstants._(); // Construtor privado — classe usada apenas como namespace

  // Chave da API Gemini lida do arquivo .env em runtime.
  // .env está no .gitignore — nunca aparece no repositório.
  // .env.example (sem a chave real) serve de referência para novos devs.
  // Retorna '' se .env não existir — nesse caso o campo de transcrição
  // fica vazio após o processamento (usuário pode digitar manualmente).
  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';

  // Chave da LocationIQ (Camada 2 de geocoding). Lida do .env em runtime.
  // 5.000 req/dia grátis; cache permanente permitido pelos ToS.
  static String get locationIqKey =>
      dotenv.env['LOCATIONIQ_KEY'] ?? '';

  // Chave da OpenWeatherMap (clima do card da Home). Lida do .env em runtime.
  // Conta grátis: 60 req/min. Vazia → card volta ao estado "em breve".
  static String get openWeatherKey =>
      dotenv.env['OPENWEATHER_API_KEY'] ?? '';

  // Chave da Groq para STT na nuvem (Whisper large-v3-turbo). Lida do .env em
  // runtime. Vazia → STT indisponível (Whisper local foi removido): o Home
  // avisa e sugere digitar. Free tier: 2.000 req/dia. Ver GroqSttService.
  static String get groqApiKey =>
      dotenv.env['GROQ_API_KEY'] ?? '';

  // ── Supabase Auth (Fase 1 — contas) ──────────────────────────────────────
  // URL do projeto Supabase e publishable key (anon). Lidas do .env em runtime.
  // Não são segredo de servidor — a mesma dupla já é usada pelo logging nativo
  // (SupabaseSink.kt). Vazias → telas de conta exibem indisponível.
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Endpoint de busca forward da LocationIQ (OSM + dados de endereço extras).
  static const locationIqEndpoint =
      'https://us1.locationiq.com/v1/search';

  // Modelo Gemini ativo. gemini-1.5-flash e gemini-2.0-flash foram desligados
  // em junho de 2026 e retornam 404. gemini-2.5-flash é o substituto estável.
  static const geminiModel = 'gemini-2.5-flash';

  // Endpoint do Gemini 2.5 Flash (suporta áudio inline em base64 + NLU).
  static const geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$geminiModel:generateContent';

  // System prompt enviado junto com o áudio ao Gemini (V2-VoicePro-Etapa3 — 10 schemas).
  // Define 10 schemas JSON fixos. A lista de ambientes existentes é injetada
  // dinamicamente pelo VoiceService._buildEnvContext() antes de cada chamada.
  static const geminiSystemPrompt =
      'Voce e o assistente do app Sopro de lembretes por localizacao. '
      'O usuario falou algo em portugues brasileiro. '
      'Transcreva o que foi dito e identifique a intencao. '
      'Retorne APENAS JSON valido (sem markdown, sem explicacao). '
      'Use EXATAMENTE um dos schemas abaixo:\n\n'
      // Criar lembrete para local existente
      '{"intent":"create_trigger","transcricao":"texto falado","environment":"nome_exato_do_banco","trigger":{"title":"titulo do lembrete","content":"detalhe opcional ou null"}}\n'
      // Cadastrar novo local
      '{"intent":"create_environment","transcricao":"texto falado","environment":{"name":"nome do local","location":"endereco ou null","radius":100}}\n'
      // Criar local e lembrete juntos
      '{"intent":"create_environment_with_trigger","transcricao":"texto falado","environment":{"name":"nome","location":null,"radius":100},"triggers":[{"title":"titulo"}]}\n'
      // Atualizar local existente
      '{"intent":"update_environment","transcricao":"texto falado","environment":{"name":"nome_exato_do_banco","changes":{"radius":200}}}\n'
      // Listar locais cadastrados
      '{"intent":"list_environments","transcricao":"texto falado"}\n'
      // Ver lembretes de um local
      '{"intent":"list_triggers","transcricao":"texto falado","environment":"nome_exato_do_banco"}\n'
      // Marcar lembrete como resolvido
      '{"intent":"resolve_trigger","transcricao":"texto falado","environment":"nome_exato_do_banco","trigger_title":"titulo do lembrete"}\n'
      // Excluir ambiente e todos os seus gatilhos
      '{"intent":"delete_environment","transcricao":"texto falado","environment":"nome_exato_do_banco"}\n'
      // Remover um gatilho específico por título
      '{"intent":"delete_trigger","transcricao":"texto falado","environment":"nome_exato_do_banco_ou_null","trigger":{"title":"titulo_aproximado"}}\n'
      // Remover todos os gatilhos de um ambiente
      '{"intent":"delete_all_triggers","transcricao":"texto falado","environment":"nome_exato_do_banco"}\n'
      // Remover TODOS os ambientes de uma vez (operacao global, sem environment)
      '{"intent":"delete_all_environments","transcricao":"texto falado"}\n'
      // Nao entendido
      '{"intent":"unknown","transcricao":"texto original falado"}\n\n'
      // ── Regra de extração do título do gatilho ─────────────────────────────
      // IMPORTANTE: para o campo trigger.title, extraia SOMENTE a acao a ser
      // realizada, sem pronomes, sem "quando chegar", sem nome do ambiente.
      // O titulo deve ser curto (maximo 50 caracteres), objetivo e no infinitivo.
      'REGRA CRITICA para trigger.title: extraia SOMENTE a acao, sem "lembra de", '
      'sem pronomes, sem nome do ambiente, maximo 50 caracteres, infinitivo.\n'
      'Exemplos de titulo correto:\n'
      '- "Me lembre de tirar o lixo quando chegar em casa" → "Tirar o lixo"\n'
      '- "Lembrar de comprar pao na padaria" → "Comprar pao"\n'
      '- "Preciso falar com o Joao sobre a infiltracao" → "Falar com Joao sobre infiltracao"\n'
      '- "Nao esquecer de pagar a conta de luz" → "Pagar conta de luz"\n\n'
      'Exemplos de intencoes:\n'
      '- "lembra de falar com joao quando chegar na obra" '
      '→ {"intent":"create_trigger","transcricao":"lembra de falar com joao quando chegar na obra","environment":"obra","trigger":{"title":"Falar com Joao","content":null}}\n'
      '- "salva esse lugar como academia" '
      '→ {"intent":"create_environment","transcricao":"salva esse lugar como academia","environment":{"name":"academia","location":null,"radius":100}}\n'
      '- "quais sao meus locais" '
      '→ {"intent":"list_environments","transcricao":"quais sao meus locais"}\n'
      '- "o que tenho pendente em casa" '
      '→ {"intent":"list_triggers","transcricao":"o que tenho pendente em casa","environment":"casa"}\n'
      '- "resolvi o lembrete da obra" '
      '→ {"intent":"resolve_trigger","transcricao":"resolvi o lembrete da obra","environment":"obra","trigger_title":""}\n'
      '- "exclui o ambiente padaria" '
      '→ {"intent":"delete_environment","transcricao":"exclui o ambiente padaria","environment":"Padaria"}\n'
      '- "remove o lembrete de tirar o lixo" '
      '→ {"intent":"delete_trigger","transcricao":"remove o lembrete de tirar o lixo","environment":null,"trigger":{"title":"Tirar o lixo"}}\n'
      '- "apaga todos os gatilhos da casa" '
      '→ {"intent":"delete_all_triggers","transcricao":"apaga todos os gatilhos da casa","environment":"Casa"}\n'
      // Frases que removem TODOS os ambientes: "excluir/apagar/remover todos os ambientes",
      // "limpar ambientes", "excluir todos os locais", "apagar tudo".
      '- "excluir todos os ambientes" '
      '→ {"intent":"delete_all_environments","transcricao":"excluir todos os ambientes"}\n'
      '- "apagar tudo" '
      '→ {"intent":"delete_all_environments","transcricao":"apagar tudo"}\n'
      '- "excluir gatilho de casa" '
      '→ {"intent":"delete_trigger","transcricao":"excluir gatilho de casa","environment":"Casa","trigger":{"title":null}}\n'
      '- "remove o lembrete da padaria" '
      '→ {"intent":"delete_trigger","transcricao":"remove o lembrete da padaria","environment":"Padaria","trigger":{"title":null}}\n'
      'Retorne APENAS o JSON valido.';

  // ── Fase 2 — prompt do ASSISTENTE (plano de acoes) ────────────────────────
  //
  // Filosofia: o Gemini NAO executa nada e NAO decide regra de negocio. Ele apenas
  // ESTRUTURA a fala do usuario em: uma resposta natural (reply), uma lista de
  // acoes (actions), uma pergunta de acompanhamento opcional (follow_up_question)
  // e atualizacoes de contexto (context_updates). O app executa as acoes.
  //
  // Enviado com o AUDIO (STT + estruturacao em UMA unica chamada). A lista de
  // ambientes existentes e o contexto de conversa sao concatenados dinamicamente
  // por VoiceService (_buildEnvContext + ConversationContext.promptSummary()).
  //
  // Retrocompatibilidade: se a fala for um comando simples, e permitido devolver
  // o schema antigo (campo "intent"); VoiceService trata ambos.
  // Fase 2.1 (Refinamento Semantico): prompt reescrito para densidade de exemplos.
  // Prosa descritiva removida; regras curtas + 7 exemplos cobrindo reutilizacao,
  // splits 2/3/4 ambientes, multiplos gatilhos, continuacao e ambiguidade.
  // A lista "Ambientes existentes" (nome + id) e injetada por
  // VoiceService._buildAssistantEnvContext() logo apos este texto.
  // Prompt do ASSISTENTE (plano de acoes) — agora MONTADO a partir da fonte
  // unica (assets/voice/voice_content.json) intercalada com os extras
  // Home-only ainda hardcoded (ver voice_prompt_assembler.dart). Saida
  // byte-identica ao literal anterior (verificado). Requer VoiceContent.load()
  // previo — feito em main() antes do runApp.
  static String get geminiAssistantPrompt =>
      assembleAssistantPrompt(VoiceContent.plan);

  // Estágio A — prompt de LIMPEZA avulso (campos de ditado simples: nome de
  // ambiente, título de gatilho). Recebe a transcrição STT bruta e devolve APENAS
  // a frase corrigida (sem JSON). Usado por VoiceService.cleanTranscript — 1
  // chamada de texto barata, fail-open (falha devolve o bruto).
  static const geminiCleanupPrompt =
      'Você recebe uma TRANSCRIÇÃO BRUTA de reconhecimento de voz em '
      'português, que pode ter erros de reconhecimento, gírias, hesitações '
      'ou palavras cortadas. Reescreva de forma limpa e natural, MANTENDO o '
      'sentido original. Corrija erros óbvios pelo contexto. Remova '
      'hesitações sem significado. Normalize gírias comuns. NUNCA invente '
      'informação que não estava na fala. NUNCA troque nomes próprios, '
      'números, datas ou horários, salvo erro gritante e óbvio. Responda '
      'APENAS com a frase corrigida, sem explicação, sem aspas.';
}
