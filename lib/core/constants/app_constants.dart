// Constantes globais do app Sopro.
// Separadas de strings.dart (que contém textos visíveis ao usuário).
class AppConstants {
  AppConstants._(); // Construtor privado — classe usada apenas como namespace

  // Chave da API Gemini para processamento de intenção de voz.
  // Obtenha em: https://aistudio.google.com (gratuita, 1 M tokens/dia).
  // Deixe em branco e o app usa apenas regex local (funciona offline).
  static const geminiApiKey = '';

  // Endpoint do modelo Gemini Flash Lite (mais rápido e gratuito).
  // gemini-2.0-flash-lite: latência ~300 ms, suficiente para UX de voz.
  static const geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash-lite:generateContent';

  // System prompt enviado ao Gemini antes da transcrição do usuário.
  // Define o contrato de resposta JSON — o modelo NUNCA deve escapar desse formato.
  static const geminiSystemPrompt =
      'Voce e o assistente do app Sopro, que gerencia lembretes por localizacao. '
      'Analise o texto do usuario e retorne APENAS um JSON valido com a intencao identificada. '
      'Formato obrigatorio:\n'
      '{intent: string, ambiente: string|null, titulo: string|null, conteudo: string|null}\n'
      'Intencoes possiveis: criar_trigger, criar_ambiente, resolver_trigger, listar_triggers, nao_entendido.\n'
      'Exemplos:\n'
      '- "lembra de falar com joao na obra" → {"intent":"criar_trigger","ambiente":"obra","titulo":"Falar com Joao","conteudo":null}\n'
      '- "cria um ambiente chamado mercado" → {"intent":"criar_ambiente","ambiente":"mercado","titulo":null,"conteudo":null}\n'
      '- "o que tenho pendente em casa?" → {"intent":"listar_triggers","ambiente":"casa","titulo":null,"conteudo":null}\n'
      '- "resolvi o lembrete da obra" → {"intent":"resolver_trigger","ambiente":"obra","titulo":null,"conteudo":null}\n'
      'Retorne APENAS o JSON, sem markdown, sem explicacao.';
}
