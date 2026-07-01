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

  // System prompt enviado junto com o áudio ao Gemini.
  // Contrato de resposta JSON com campo 'transcricao' obrigatório:
  //   - transcricao: o que o usuário disse (pt-BR, texto limpo)
  //   - intent: ação identificada
  //   - ambiente: nome do local mencionado
  //   - titulo: título do lembrete / ação a executar
  //   - conteudo: detalhe adicional opcional
  static const geminiSystemPrompt =
      'Voce e o assistente do app Sopro de lembretes por localizacao. '
      'O usuario falou algo em portugues brasileiro. '
      'Transcreva o que foi dito e identifique a intencao. '
      'Retorne APENAS JSON valido (sem markdown, sem explicacao):\n'
      '{"transcricao":"texto exato falado","intent":"string","ambiente":"string|null","titulo":"string|null","conteudo":"string|null"}\n'
      'Intencoes possiveis:\n'
      '  criar_trigger    = criar lembrete para disparar quando chegar num local\n'
      '  criar_ambiente   = salvar/cadastrar um novo local no app\n'
      '  resolver_trigger = marcar lembrete como resolvido ou apagar\n'
      '  listar_triggers  = ver lembretes pendentes de um local\n'
      '  nao_entendido    = nao foi possivel identificar\n'
      'Exemplos:\n'
      '- audio: "lembra de falar com joao quando chegar na obra" '
      '→ {"transcricao":"lembra de falar com joao quando chegar na obra","intent":"criar_trigger","ambiente":"obra","titulo":"Falar com Joao","conteudo":null}\n'
      '- audio: "salva esse lugar como academia" '
      '→ {"transcricao":"salva esse lugar como academia","intent":"criar_ambiente","ambiente":"academia","titulo":null,"conteudo":null}\n'
      '- audio: "o que tenho pendente em casa" '
      '→ {"transcricao":"o que tenho pendente em casa","intent":"listar_triggers","ambiente":"casa","titulo":null,"conteudo":null}\n'
      '- audio: "resolvi o lembrete da obra" '
      '→ {"transcricao":"resolvi o lembrete da obra","intent":"resolver_trigger","ambiente":"obra","titulo":null,"conteudo":null}\n'
      'Retorne APENAS o JSON.';

  // System prompt para processamento de TEXTO (re-análise após edição manual).
  // Usado quando o usuário corrige a transcrição e toca "Re-analisar".
  static const geminiTextPrompt =
      'Voce e o assistente do app Sopro de lembretes por localizacao. '
      'Analise o texto abaixo (digitado ou corrigido pelo usuario) e identifique a intencao. '
      'Retorne APENAS JSON valido (sem markdown):\n'
      '{"transcricao":"texto recebido","intent":"string","ambiente":"string|null","titulo":"string|null","conteudo":"string|null"}\n'
      'Intencoes: criar_trigger, criar_ambiente, resolver_trigger, listar_triggers, nao_entendido.\n'
      'Retorne APENAS o JSON.';
}
