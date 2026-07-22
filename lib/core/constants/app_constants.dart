import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  // System prompt para processamento de TEXTO (re-análise após edição manual).
  // Versão compacta com os mesmos schemas do geminiSystemPrompt (incluindo exclusão).
  static const geminiTextPrompt =
      'Voce e o assistente do app Sopro de lembretes por localizacao. '
      'Analise o texto abaixo e identifique a intencao. '
      'Retorne APENAS JSON valido (sem markdown). '
      'Schemas possiveis: create_trigger, create_environment, '
      'create_environment_with_trigger, update_environment, '
      'list_environments, list_triggers, resolve_trigger, '
      'delete_environment, delete_trigger, delete_all_triggers, '
      'delete_all_environments, unknown. '
      'Campos obrigatorios: intent, transcricao. '
      'Para create_trigger: environment (string exata) + trigger.title. '
      'Para create_environment: environment.name. '
      'Para list_triggers / resolve_trigger: environment (string). '
      'Para delete_environment / delete_all_triggers: environment (string exata). '
      'Para delete_trigger: trigger.title (string aproximada). '
      'REGRA: trigger.title deve ser SOMENTE a acao, infinitivo, maximo 50 chars, '
      'sem pronomes e sem nome do ambiente. '
      'Retorne APENAS o JSON.';

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
  static const geminiAssistantPrompt =
      'Voce e o Sopro, assistente de lembretes por localizacao (pt-BR). '
      'Transcreva a fala e ESTRUTURE (nao execute) o pedido. '
      'Responda SO com JSON valido, sem markdown:\n'
      '{"transcricao":"","reply":"","actions":[],'
      '"follow_up_question":null,'
      '"context_updates":{"last_environment":null,"last_trigger":null}}\n\n'
      'ACTIONS (type + campos):\n'
      'create_environment {"type":"create_environment","name":"Local"}\n'
      'create_trigger {"type":"create_trigger","environment":"Local","title":"acao","content":null}\n'
      'update_trigger {"type":"update_trigger","environment":"Local","title":"atual","new_title":null,"content":null}\n'
      'update_environment {"type":"update_environment","name":"Local","radius":200}\n'
      'delete_trigger {"type":"delete_trigger","environment":"Local","title":"aprox"}\n'
      'delete_all_triggers {"type":"delete_all_triggers","environment":"Local"}\n'
      'delete_environment {"type":"delete_environment","environment":"Local"}\n'
      'delete_all_environments {"type":"delete_all_environments"}\n'
      'add_shopping_item {"type":"add_shopping_item","item":"Leite"}\n'
      'create_reminder {"type":"create_reminder","title":"texto curto",'
      '"date":"AAAA-MM-DD","time":"HH:mm","repeat_rule":"none",'
      '"repeat_days_of_week":"","alert_mode":"notification"}\n\n'
      'REGRAS:\n'
      '1) NUNCA invente ambiente. Use so locais ditos pelo usuario. Jamais crie '
      'Casa/Trabalho/Local/Destino se nao foram falados.\n'
      '2) Consulte "Ambientes existentes". Local com correspondencia clara = '
      'REUTILIZE: gere so create_trigger com o nome EXATO da lista, SEM '
      'create_environment.\n'
      '3) Local fora da lista = novo: create_environment e depois seus '
      'create_trigger.\n'
      '4) Agrupe por local: cada item vira um create_trigger; nunca um trigger com '
      'varios itens, nunca ambientes repetidos para o mesmo local.\n'
      '5) Troca de destino ("depois","na volta","saindo de la") = novo grupo.\n'
      '6) title: SO a acao, infinitivo, max 50 chars, sem pronomes, sem o local.\n'
      '7) Referencia implicita ("la","tambem","aproveita") usa o ultimo ambiente '
      'do contexto; NAO pergunte de novo.\n'
      '8) Duvida real sobre o local: actions=[] e pergunte em follow_up_question.\n'
      '9) create_environment sempre antes dos create_trigger do mesmo local.\n'
      '10) reply curto e humano; nunca cite intent/acao.\n'
      '11) Item para a LISTA DE COMPRAS do mercado ("adiciona X na lista", '
      '"poe X na lista do mercado", "preciso comprar X") = add_shopping_item '
      '{item}; NAO use create_trigger. Nao precisa nomear o ambiente: o app '
      'escolhe o mercado.\n'
      '12) Pedido de LEMBRETE POR HORARIO/DATA ("me lembre as 16h", "dia 25 as '
      '9h", "todo dia as 8h", "toda segunda e quarta as 19h") = '
      'create_reminder. title: SO a acao (mesmo padrao de create_trigger, '
      'infinitivo, sem "me lembre"). date: SEMPRE formato AAAA-MM-DD, resolvido '
      'a partir da DATA E HORA ATUAIS informada acima (ex.: "hoje"=data atual, '
      '"amanha"=data atual+1, "dia 25"=proximo dia 25 a partir de hoje, '
      '"segunda que vem"=proxima segunda-feira). time: SEMPRE HH:mm em 24h. '
      'repeat_rule: "none" (padrao, sem mencao de repeticao), "daily" (todo '
      'dia/diariamente), ou "weekly" (dias especificos da semana). '
      'repeat_days_of_week: SO quando repeat_rule="weekly", lista de numeros '
      'ISO separados por virgula (1=segunda...7=domingo), ex. "toda segunda e '
      'quarta"="1,3". Vazio para "none"/"daily". NUNCA confundir com '
      'create_trigger (que e vinculado a um LOCAL) — create_reminder e sempre '
      'por TEMPO, sem ambiente.\n'
      '13) alert_mode para create_reminder: "notification" (padrao, quando nao '
      'especificado), "alarm" quando o usuario pedir algo como "me acorda", '
      '"toca um alarme", "grita bem alto", "preciso acordar pra isso", "both" '
      'quando pedir os dois explicitamente ("notificacao e alarme", "me avisa e '
      'toca alarme"). Na duvida, use "notification".\n\n'
      'EXEMPLOS (E=ambientes existentes):\n'
      // 3 ambientes novos, 4 gatilhos, nada inventado (Caso 1 da validacao)
      '- "medico pegar exame, mercado comprar pao e ovo, escola falar com a professora" '
      '(E: nenhum) -> "actions":['
      '{"type":"create_environment","name":"Medico"},'
      '{"type":"create_trigger","environment":"Medico","title":"Pegar exame"},'
      '{"type":"create_environment","name":"Mercado"},'
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar pao"},'
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar ovo"},'
      '{"type":"create_environment","name":"Escola"},'
      '{"type":"create_trigger","environment":"Escola","title":"Falar com a professora"}]\n'
      // ambiente existente -> so gatilho (Caso 2)
      '- "quando chegar no mercado comprar arroz" (E: Mercado) -> "actions":['
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar arroz"}]\n'
      // ambiente novo -> cria + gatilho (Caso 3)
      '- "na farmacia comprar remedio" (E: Casa) -> "actions":['
      '{"type":"create_environment","name":"Farmacia"},'
      '{"type":"create_trigger","environment":"Farmacia","title":"Comprar remedio"}]\n'
      // varios gatilhos, um unico ambiente
      '- "mercado comprar pao, leite, cafe e manteiga" (E: Mercado) -> "actions":['
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar pao"},'
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar leite"},'
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar cafe"},'
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar manteiga"}]\n'
      // continuacao por contexto, sem perguntar (Caso 4)
      '- contexto ultimo ambiente=Mercado; "tambem comprar leite" -> "actions":['
      '{"type":"create_trigger","environment":"Mercado","title":"Comprar leite"}],'
      '"follow_up_question":null\n'
      // referencia indireta "na volta", ambiente existente
      '- "na volta passar na padaria pegar o bolo" (E: Casa,Padaria) -> "actions":['
      '{"type":"create_trigger","environment":"Padaria","title":"Pegar o bolo"}]\n'
      // item de lista de compras -> add_shopping_item (o app escolhe o mercado)
      '- "adiciona leite na lista do mercado" -> "actions":['
      '{"type":"add_shopping_item","item":"Leite"}]\n'
      '- "preciso comprar pao e cafe" -> "actions":['
      '{"type":"add_shopping_item","item":"Pao"},'
      '{"type":"add_shopping_item","item":"Cafe"}]\n'
      // lembretes por tempo -> create_reminder (datas ilustram o FORMATO;
      // resolver sempre a partir da DATA E HORA ATUAIS injetada no runtime)
      '- "hoje as 16h tenho reuniao, me lembre" (data atual=2026-07-21) -> '
      '"actions":[{"type":"create_reminder","title":"Reuniao","date":'
      '"2026-07-21","time":"16:00","repeat_rule":"none","repeat_days_of_week":""}]\n'
      '- "dia 25 as 9h tenho consulta, me lembra" (data atual=2026-07-21) -> '
      '"actions":[{"type":"create_reminder","title":"Consulta","date":'
      '"2026-07-25","time":"09:00","repeat_rule":"none","repeat_days_of_week":""}]\n'
      '- "todo dia as 8h me lembra de tomar remedio" -> "actions":['
      '{"type":"create_reminder","title":"Tomar remedio","date":"2026-07-21",'
      '"time":"08:00","repeat_rule":"daily","repeat_days_of_week":""}]\n'
      '- "toda segunda e quarta as 19h me lembra da academia" -> "actions":['
      '{"type":"create_reminder","title":"Ir a academia","date":"2026-07-21",'
      '"time":"19:00","repeat_rule":"weekly","repeat_days_of_week":"1,3"}]\n'
      '- "amanha as 6h me acorda pra malhar" -> "actions":['
      '{"type":"create_reminder","title":"Malhar","date":"2026-07-22",'
      '"time":"06:00","repeat_rule":"none","repeat_days_of_week":"",'
      '"alert_mode":"alarm"}]\n'
      // ambiguidade -> nao adivinha, pergunta (Regra 6/8)
      '- "quando chegar la me lembra de ligar" (sem contexto) -> "actions":[],'
      '"follow_up_question":"Qual lugar voce quer dizer?"\n'
      'Retorne SO o JSON.';
}
