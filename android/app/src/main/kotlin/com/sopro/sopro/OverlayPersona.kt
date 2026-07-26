package com.sopro.sopro

// OverlayPersona — Estágio 5 da reorganização do overlay de voz.
//
// Fonte ÚNICA das frases faladas do overlay (speak/speakTyped), antes literais
// espalhados por FloatingVoiceService e OverlaySkills. Espelha o BehaviorEngine/
// AssistantPersona do lado Dart: ajustar o tom depois é editar aqui, sem caçar
// string por string.
//
// COMPORTAMENTAL-PRESERVADO: texto verbatim. Interpolações viram parâmetros de
// função — o valor passado no call site é idêntico ao de antes. Não inclui os
// prompts de parâmetro-faltando de prosódia distinta por pipeline nem as
// perguntas de confirmação destrutiva (essas já são fonte única em OverlaySkills).
object OverlayPersona {

    // ── Captura / não entendi ────────────────────────────────────────────
    val notHeard = "Não consegui ouvir você."
    val apiKeyMissing = "Chave da API não configurada. Abra o Sopro uma vez."
    val audioProcessingFailed = "Não consegui processar o áudio."
    val notUnderstoodPressAgain = "Não entendi. Pressione novamente para tentar."
    val notUnderstoodRepeat = "Não consegui entender. Pode repetir?"
    val commandNotUnderstood = "Não consegui entender esse comando. Pode repetir de outra forma?"
    val itemNotUnderstood = "Não entendi o item. Pode repetir?"

    // ── Ambientes ────────────────────────────────────────────────────────
    fun environmentCreatedReady(name: String) = "Pronto! Ambiente $name criado."
    fun environmentCreated(name: String) = "Ambiente $name criado."
    fun environmentCreatedOpenApp(name: String) =
        "Ambiente $name criado. Abra o app para definir o endereço."
    val couldNotCreateEnvironment = "Não consegui criar o ambiente."
    fun couldNotCreateNow(name: String) = "Não consegui criar $name agora."
    fun environmentRemoved(name: String) = "Ambiente $name removido."
    fun environmentNotFound(name: String) = "Não encontrei o ambiente $name."
    fun environmentNotFoundCreate(name: String) =
        "Não encontrei o ambiente $name. Quer que eu crie agora?"
    fun environmentNotFoundVerify(name: String) =
        "Não encontrei o ambiente $name. Verifique o nome e tente novamente."
    val allEnvironmentsRemoved = "Todos os ambientes foram removidos."
    val noEnvironmentsYet = "Você ainda não tem nenhum ambiente cadastrado."

    // ── Nome / perguntas de ambiente ─────────────────────────────────────
    val askPlaceName = "Qual é o nome do lugar? Por exemplo: casa, trabalho ou academia."
    val askEnvironmentName = "Qual é o nome do ambiente?"
    val askWhichEnvironmentForReminder = "Em qual ambiente devo salvar esse lembrete?"
    val askWhichEnvironmentToRemove = "Qual ambiente você quer remover?"
    val askWhichEnvironmentToRemoveReminder = "De qual ambiente devo remover o lembrete?"
    val askWhichEnvironmentToRemoveReminders = "De qual ambiente devo remover os lembretes?"

    // ── Lembretes ────────────────────────────────────────────────────────
    fun reminderSaved(title: String, env: String) =
        "Anotado! Vou te lembrar de $title quando chegar em $env."
    fun environmentAndReminderCreated(env: String, title: String) =
        "Pronto! Ambiente $env criado e lembrete '$title' registrado."
    val environmentCreatedReminderFailed = "Ambiente criado, mas não consegui salvar o lembrete."
    val reminderCancelled = "Tudo bem, lembrete cancelado."
    val confirmCreateEnvironmentYesNo =
        "Não entendi. Diga 'sim' para criar o ambiente ou 'não' para cancelar."
    val reminderExampleTry = "Não entendi. Tente: 'lembra de X quando chegar em Y'."
    val reminderExampleSay = "Não entendi. Diga: lembra de X quando chegar em Y."
    val reminderRemoved = "Lembrete removido."
    fun allRemindersRemoved(env: String) = "Todos os lembretes de $env foram removidos."
    fun reminderNotFoundIn(env: String) = "Não encontrei esse lembrete em $env."

    // ── Localização ──────────────────────────────────────────────────────
    val locationUnavailable = "Não foi possível obter sua localização."
    val locationUnavailableManual =
        "Não foi possível obter sua localização. Abra o app e defina manualmente."
    fun confirmUseCurrentLocation(name: String) =
        "Você deseja usar sua localização atual para criar $name?"
    fun openAppForAddress(name: String) =
        "Tudo bem. Abra o app Sopro para escolher o endereço de $name."

    // ── Confirmação / cancelamento ───────────────────────────────────────
    val cancelledOk = "Tudo bem, cancelei."

    // ── Compras ──────────────────────────────────────────────────────────
    val couldNotSaveNow = "Não consegui salvar agora. Tente de novo."
    val marketNameRepeat = "Não peguei bem — pode falar só o nome do mercado?"
    val noMarketYet =
        "Ainda não tenho nenhum mercado salvo. Quer que eu crie um agora, ou prefere fazer isso pelo app?"
    // [names] e [items] já vêm formatados (humanJoin) do call site.
    fun whichMarket(names: String, items: String) =
        "Você tem $names salvos — em qual eu coloco $items?"
    val addToListWhat = "O que você quer adicionar à lista?"

    // ── Plano (resumo agregado) ──────────────────────────────────────────
    val couldNotFinishRetry = "Não consegui concluir agora. Pode tentar de novo?"
    fun partialFailure(failed: Int) = "Fiz a maior parte. $failed não deram certo."
    val done = "Pronto!"
}
