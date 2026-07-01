import 'package:flutter_dotenv/flutter_dotenv.dart';

// Constantes globais do app Sopro.
// Separadas de strings.dart (que contém textos visíveis ao usuário).
class AppConstants {
  AppConstants._(); // Construtor privado — classe usada apenas como namespace

  // Chave da API Gemini lida do arquivo .env em runtime.
  // .env está no .gitignore — nunca aparece no repositório.
  // .env.example (sem a chave real) serve de referência para novos devs.
  // Retorna '' se .env não existir ou a variável não estiver definida —
  // nesse caso o app usa apenas regex local (funciona offline).
  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';

  // Endpoint do modelo Gemini 2.0 Flash (mais rápido, gratuito, suporta pt-BR).
  // gemini-2.0-flash-lite foi descontinuado — usar gemini-2.0-flash.
  static const geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  // System prompt enviado ao Gemini antes da transcrição do usuário.
  // Regras críticas:
  //   - Retornar APENAS JSON puro, nunca markdown (```json ... ```)
  //   - criar_trigger = lembrete a disparar NUM LOCAL JÁ EXISTENTE
  //   - criar_ambiente = criar UM NOVO LOCAL no app
  //   - Se o local mencionado é novo/desconhecido, preferir criar_ambiente
  static const geminiSystemPrompt =
      'Voce e o assistente do app Sopro, que gerencia lembretes por localizacao. '
      'Analise o texto do usuario e retorne APENAS um JSON valido (sem markdown, sem explicacao). '
      'Formato obrigatorio: {"intent":"string","ambiente":"string|null","titulo":"string|null","conteudo":"string|null"}\n'
      'Intencoes:\n'
      '  criar_trigger    = criar lembrete para disparar quando chegar num local\n'
      '  criar_ambiente   = salvar/cadastrar um novo local no app\n'
      '  resolver_trigger = marcar lembrete como resolvido/apagar\n'
      '  listar_triggers  = ver lembretes pendentes de um local\n'
      '  nao_entendido    = nao foi possivel classificar\n'
      'Exemplos:\n'
      '- "lembra de falar com joao quando eu chegar na obra" → {"intent":"criar_trigger","ambiente":"obra","titulo":"Falar com Joao","conteudo":null}\n'
      '- "lembra de comprar leite no mercado" → {"intent":"criar_trigger","ambiente":"mercado","titulo":"Comprar leite","conteudo":null}\n'
      '- "salva esse lugar como academia" → {"intent":"criar_ambiente","ambiente":"academia","titulo":null,"conteudo":null}\n'
      '- "cria um ambiente chamado mercado" → {"intent":"criar_ambiente","ambiente":"mercado","titulo":null,"conteudo":null}\n'
      '- "adiciona esse local como trabalho" → {"intent":"criar_ambiente","ambiente":"trabalho","titulo":null,"conteudo":null}\n'
      '- "o que tenho pendente em casa?" → {"intent":"listar_triggers","ambiente":"casa","titulo":null,"conteudo":null}\n'
      '- "resolvi o lembrete da obra" → {"intent":"resolver_trigger","ambiente":"obra","titulo":null,"conteudo":null}\n'
      '- "pode apagar o lembrete de comprar leite" → {"intent":"resolver_trigger","ambiente":null,"titulo":"Comprar leite","conteudo":null}\n'
      'Retorne APENAS o JSON, sem nenhum texto adicional.';
}
