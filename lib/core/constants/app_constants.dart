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
      'delete_environment, delete_trigger, delete_all_triggers, unknown. '
      'Campos obrigatorios: intent, transcricao. '
      'Para create_trigger: environment (string exata) + trigger.title. '
      'Para create_environment: environment.name. '
      'Para list_triggers / resolve_trigger: environment (string). '
      'Para delete_environment / delete_all_triggers: environment (string exata). '
      'Para delete_trigger: trigger.title (string aproximada). '
      'REGRA: trigger.title deve ser SOMENTE a acao, infinitivo, maximo 50 chars, '
      'sem pronomes e sem nome do ambiente. '
      'Retorne APENAS o JSON.';
}
