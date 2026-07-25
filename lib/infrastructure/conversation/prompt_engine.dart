// Prompt Engine — monta o prompt enviado ao LLM a partir das peças do framework.
//
// Formaliza voice_structure_doc/architecture/07-Prompt-Engine.md: centraliza a
// engenharia de prompt e define a ORDEM das seções, mantendo o resto do sistema
// (Skills, Planner) alheio a isso.
//
// Estágio 5 (comportamento-preservado): produz EXATAMENTE a mesma string que
// voice_service.dart montava inline —
//   geminiAssistantPrompt + envContext + dateTimeContext +
//   (contextSummary.isNotEmpty ? '\n$contextSummary' : '')
// Só reorganiza a montagem. Provider-independente: devolve texto puro, sem saber
// que o destino é o Gemini — pronto para troca de modelo futura.
//
// A "entrada do usuário" (seção 7 do spec) NÃO entra aqui: no áudio ela é o
// inline_data; no texto é anexada na camada de envio ("Comando do usuario: ...").
class PromptEngine {
  const PromptEngine();

  // Ordem do spec 07:
  //   1/2 instruções do sistema + personalidade  → [systemPersona]
  //   3   contexto da conversa (ambientes)        → [environmentContext]
  //       data/hora atual                          → [dateTimeContext]
  //   4   memórias relevantes                      → [memorySummary]
  //   6   dados da skill ativa                     → [activeSkillContext]
  //
  // [environmentContext] e [dateTimeContext] já vêm com '\n' inicial (como antes).
  // [memorySummary] e [activeSkillContext] só entram quando não vazios — hoje o
  // segundo é sempre vazio (slot para contexto por-skill futuro), então a saída
  // permanece idêntica.
  String build({
    required String systemPersona,
    String environmentContext = '',
    String dateTimeContext = '',
    String memorySummary = '',
    String activeSkillContext = '',
  }) {
    final buf = StringBuffer(systemPersona)
      ..write(environmentContext)
      ..write(dateTimeContext);
    if (memorySummary.isNotEmpty) buf.write('\n$memorySummary');
    if (activeSkillContext.isNotEmpty) buf.write('\n$activeSkillContext');
    return buf.toString();
  }
}
