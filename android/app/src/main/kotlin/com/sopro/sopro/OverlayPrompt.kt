package com.sopro.sopro

import java.util.Calendar

// OverlayPrompt — monta o prompt de PLANO (ACTIONS/REGRAS/EXEMPLOS) do overlay a
// partir da FONTE UNICA (VoiceContent / assets/voice/voice_content.json), a mesma
// lida pelo Home (Dart). Antes o texto era hardcoded aqui, cópia divergente do
// AppConstants.geminiAssistantPrompt.
//
// Etapa 2 (paridade total): o overlay agora executa TODAS as 11 ações do Home
// (inclusive update_trigger, update_environment, create_reminder, weather_query),
// então usa o prompt COMPLETO da fonte única — os mesmos schema/regras/exemplos
// canônicos do Home. A prioridade destrutiva (regra + exemplos de delete), que o
// Home ainda não tem, é anexada do próprio asset (segmento delete_priority) para
// NÃO regredir o overlay.
//
// O contexto de ambientes (nomes do SQLite) continua montado aqui — é específico
// do overlay e injetado antes do rodapé, como antes.
object OverlayPrompt {

    // Linha de contexto: ambientes existentes lidos do SQLite (nomes exatos).
    private fun environmentContext(envNames: List<String>): String =
        if (envNames.isNotEmpty())
            "Ambientes existentes (reutilize pelo nome EXATO; nao recrie): " +
                envNames.joinToString(", ")
        else
            "Ambientes existentes: nenhum. Todo local citado e novo."

    // DATA E HORA ATUAIS do aparelho — MESMO texto/formato do _dateTimeContext do
    // Home (voice_service.dart), só reimplementado com Calendar. O Gemini usa isto
    // para resolver "hoje"/"amanha"/"segunda que vem"/datas relativas em
    // create_reminder; sem isto, o Overlay ancorava nas datas ILUSTRATIVAS dos
    // exemplos (bug da Etapa 2). Nomes de dia em pt-BR sem acento, iguais ao Dart.
    private fun dateTimeContext(): String {
        val cal = Calendar.getInstance()
        val weekdayNames = arrayOf("segunda-feira", "terca-feira", "quarta-feira",
            "quinta-feira", "sexta-feira", "sabado", "domingo")
        val dow = cal.get(Calendar.DAY_OF_WEEK)              // 1=Dom..7=Sab
        val iso = if (dow == Calendar.SUNDAY) 7 else dow - 1 // 1=Seg..7=Dom
        fun p2(n: Int) = n.toString().padStart(2, '0')
        return "\nDATA E HORA ATUAIS: ${cal.get(Calendar.YEAR)}-" +
            "${p2(cal.get(Calendar.MONTH) + 1)}-${p2(cal.get(Calendar.DAY_OF_MONTH))} " +
            "${p2(cal.get(Calendar.HOUR_OF_DAY))}:${p2(cal.get(Calendar.MINUTE))} " +
            "(${weekdayNames[iso - 1]}). " +
            "Use isso para resolver \"hoje\", \"amanha\", \"essa semana\", nomes de dias " +
            "da semana e datas relativas."
    }

    // Prompt de PLANO completo montado do asset + prioridade destrutiva + o
    // contexto de ambientes interpolado antes do rodapé.
    fun buildPlanPrompt(envNames: List<String>): String {
        val envCtx = environmentContext(envNames)
        return buildString {
            append(VoiceContent.plan("header"))
            append(VoiceContent.plan("format"))
            append(VoiceContent.plan("entrada"))
            // ACTIONS: todas as 11 ações (mesmo bloco do Home).
            append(VoiceContent.plan("actions_header"))
            append(VoiceContent.plan("actions_full"))
            // REGRAS: prioridade destrutiva PRIMEIRO (proeminente, como era antes da
            // unificação) — evita que create_reminder "roube" comandos de apagar —,
            // depois as regras numeradas comuns.
            append(VoiceContent.plan("rules_header"))
            append(VoiceContent.plan("delete_priority_rule"))
            append(VoiceContent.plan("rules_full"))
            // EXEMPLOS: exemplos de delete (single + all) PRIMEIRO (ancoram a intenção
            // de apagar 1 gatilho/local específico), depois os demais; dica de clima ao fim.
            append(VoiceContent.plan("examples_header"))
            append(VoiceContent.plan("delete_priority_examples"))
            append(VoiceContent.plan("examples_full"))
            append(VoiceContent.plan("weather_hint"))
            // Contexto de ambientes + DATA E HORA ATUAIS reais (mesma ordem do Dart:
            // envContext e depois dateTimeContext) + rodapé. A data real é o que
            // permite ao Gemini resolver datas relativas em create_reminder.
            append(envCtx).append('\n')
            append(dateTimeContext()).append('\n')
            append(VoiceContent.plan("footer"))
        }
    }
}
