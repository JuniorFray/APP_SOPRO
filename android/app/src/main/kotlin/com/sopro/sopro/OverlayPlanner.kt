package com.sopro.sopro

// OverlayPlanner — Estágio 4 da reorganização do overlay de voz.
//
// Isola as GUARDAS de roteamento que viviam dentro de executePlan (plano vazio /
// destrutivo / só-compras / 1 ambiente / construtivo) e a resolução do estado de
// espera ativo de executeVoiceResult. MESMA ordem de prioridade, MESMAS condições
// — só fora da função gigante.
//
// COMPORTAMENTAL-PRESERVADO: o Planner apenas DECIDE a rota; a EXECUÇÃO (fala, DB,
// GPS, Skills) continua no serviço. Nenhum efeito colateral aqui.
internal object OverlayPlanner {

    // Tipos de ação destrutiva (mesma lista da guarda original de executePlan).
    private val DESTRUCTIVE = setOf(
        "delete_environment", "delete_all_environments",
        "delete_trigger", "delete_all_triggers",
    )

    // Decide a rota de um plano, na MESMA ordem de prioridade de antes:
    // vazio → destrutivo → só-compras → 1 ambiente (nome válido) → construtivo.
    // [isBlockedName] espelha a checagem BLOCKED_ENV_NAMES do serviço.
    fun routePlan(
        plan: FloatingVoiceService.PlanResult,
        isBlockedName: (String) -> Boolean,
    ): PlanRoute {
        if (plan.actions.isEmpty()) return PlanRoute.Empty

        val destructive = plan.actions.firstOrNull { it.type in DESTRUCTIVE }
        if (destructive != null) return PlanRoute.Destructive(destructive)

        if (plan.actions.all { it.type == "add_shopping_item" }) return PlanRoute.Shopping

        // Consulta de clima (Etapa 2): fala o tempo, não muta o banco nem usa o
        // resumo genérico do loop. Tratada em rota própria (paridade com o Home).
        if (plan.actions.size == 1 && plan.actions[0].type == "weather_query")
            return PlanRoute.Weather(plan.actions[0])

        if (plan.actions.size == 1 && plan.actions[0].type == "create_environment") {
            val name = plan.actions[0].str("name", "environment")
            if (name != null && name.isNotBlank() && !isBlockedName(name))
                return PlanRoute.SingleEnvironment(name.trim())
        }

        return PlanRoute.Construct
    }

    // Estado de espera ATIVO da conversa: o estado corrente, ou null se expirou.
    // Substitui os repetidos "voiceState == X && !stateExpired" de executeVoiceResult.
    fun activeAwaiting(state: String?, expired: Boolean): String? =
        if (expired) null else state
}

// Rota de um plano (decisão do Planner). A execução de cada rota fica no serviço.
internal sealed class PlanRoute {
    object Empty : PlanRoute()
    data class Destructive(val action: FloatingVoiceService.PlanAction) : PlanRoute()
    object Shopping : PlanRoute()
    data class Weather(val action: FloatingVoiceService.PlanAction) : PlanRoute()
    data class SingleEnvironment(val name: String) : PlanRoute()
    object Construct : PlanRoute()
}
