// Monta o geminiAssistantPrompt (Home) a partir da fonte unica
// (assets/voice/voice_content.json, resolvida por [p]). Desde a Etapa 2 TODAS as
// acoes vivem no asset — inclusive update_trigger, update_environment,
// create_reminder e weather_query — entao nao ha mais texto de prompt hardcoded
// aqui. Saida byte-identica ao literal original (verificado). Puro (sem Flutter)
// para permitir verificacao byte-a-byte fora do runtime.
String assembleAssistantPrompt(String Function(String) p) =>
    p('header') +
    p('format') +
    p('entrada') +
    p('actions_header') +
    p('actions_full') +
    p('rules_header') +
    p('rules_full') +
    p('examples_header') +
    p('examples_full') +
    p('footer');
