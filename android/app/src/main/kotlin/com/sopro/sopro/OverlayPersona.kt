package com.sopro.sopro

// OverlayPersona — frases faladas do overlay (speak/speakTyped).
//
// Etapa 1 (unificação): o SUBSET comum ao Home passou para a fonte única
// (VoiceContent / assets/voice/voice_content.json) — as 11 frases marcadas
// [FONTE UNICA] abaixo leem de lá (canônico = Home). Onde o texto do overlay
// divergia do Home, o overlay adota o canônico (ex.: "Quer criar agora?" no lugar
// de "Quer que eu crie agora?"). As demais frases são específicas do overlay (sem
// equivalente no Home) e seguem como literais aqui.
//
// {placeholders} ({name}/{title}/{env}/{failed}) são resolvidos no call site, como
// as interpolações anteriores. Requer VoiceContent.ensureLoaded() prévio (feito no
// onCreate do FloatingVoiceService) — sem isso, o getter cai em "" (fallback).
object OverlayPersona {

    // ── Captura / não entendi (overlay-only) ─────────────────────────────
    val notHeard = "Não consegui ouvir você."
    val apiKeyMissing = "Chave da API não configurada. Abra o Sopro uma vez."
    val audioProcessingFailed = "Não consegui processar o áudio."
    val notUnderstoodPressAgain = "Não entendi. Pressione novamente para tentar."
    val notUnderstoodRepeat = "Não consegui entender. Pode repetir?"
    val commandNotUnderstood = "Não consegui entender esse comando. Pode repetir de outra forma?"
    val itemNotUnderstood = "Não entendi o item. Pode repetir?"

    // ── Ambientes ────────────────────────────────────────────────────────
    // [FONTE UNICA]
    fun environmentCreatedReady(name: String) =
        VoiceContent.persona("environmentCreatedReady").replace("{name}", name)
    // [FONTE UNICA]
    fun environmentCreated(name: String) =
        VoiceContent.persona("environmentCreated").replace("{name}", name)
    fun environmentCreatedOpenApp(name: String) =
        "Ambiente $name criado. Abra o app para definir o endereço."
    val couldNotCreateEnvironment = "Não consegui criar o ambiente."
    fun couldNotCreateNow(name: String) = "Não consegui criar $name agora."
    // [FONTE UNICA]
    fun environmentRemoved(name: String) =
        VoiceContent.persona("environmentRemoved").replace("{name}", name)
    // [FONTE UNICA]
    fun environmentNotFound(name: String) =
        VoiceContent.persona("environmentNotFound").replace("{name}", name)
    // [FONTE UNICA] (adota o canônico do Home: "Quer criar agora?")
    fun environmentNotFoundCreate(name: String) =
        VoiceContent.persona("environmentNotFoundCreate").replace("{name}", name)
    fun environmentNotFoundVerify(name: String) =
        "Não encontrei o ambiente $name. Verifique o nome e tente novamente."
    val allEnvironmentsRemoved = "Todos os ambientes foram removidos."
    // [FONTE UNICA] (adota o canônico do Home: "...nenhum local cadastrado.")
    val noEnvironmentsYet get() = VoiceContent.persona("noEnvironmentsYet")

    // ── Nome / perguntas de ambiente (overlay-only) ──────────────────────
    val askPlaceName = "Qual é o nome do lugar? Por exemplo: casa, trabalho ou academia."
    val askEnvironmentName = "Qual é o nome do ambiente?"
    val askWhichEnvironmentForReminder = "Em qual ambiente devo salvar esse lembrete?"
    val askWhichEnvironmentToRemove = "Qual ambiente você quer remover?"
    val askWhichEnvironmentToRemoveReminder = "De qual ambiente devo remover o lembrete?"
    val askWhichEnvironmentToRemoveReminders = "De qual ambiente devo remover os lembretes?"

    // ── Lembretes ────────────────────────────────────────────────────────
    // [FONTE UNICA]
    fun reminderSaved(title: String, env: String) =
        VoiceContent.persona("reminderSaved").replace("{title}", title).replace("{env}", env)
    fun environmentAndReminderCreated(env: String, title: String) =
        "Pronto! Ambiente $env criado e lembrete '$title' registrado."
    val environmentCreatedReminderFailed = "Ambiente criado, mas não consegui salvar o lembrete."
    val reminderCancelled = "Tudo bem, lembrete cancelado."
    val confirmCreateEnvironmentYesNo =
        "Não entendi. Diga 'sim' para criar o ambiente ou 'não' para cancelar."
    val reminderExampleTry = "Não entendi. Tente: 'lembra de X quando chegar em Y'."
    val reminderExampleSay = "Não entendi. Diga: lembra de X quando chegar em Y."
    // [FONTE UNICA]
    val reminderRemoved get() = VoiceContent.persona("reminderRemoved")
    // [FONTE UNICA] (adota o canônico do Home: "...de $env removidos.")
    fun allRemindersRemoved(env: String) =
        VoiceContent.persona("allRemindersRemoved").replace("{env}", env)
    fun reminderNotFoundIn(env: String) = "Não encontrei esse lembrete em $env."

    // ── Localização (overlay-only) ───────────────────────────────────────
    val locationUnavailable = "Não foi possível obter sua localização."
    val locationUnavailableManual =
        "Não foi possível obter sua localização. Abra o app e defina manualmente."
    fun confirmUseCurrentLocation(name: String) =
        "Você deseja usar sua localização atual para criar $name?"
    fun openAppForAddress(name: String) =
        "Tudo bem. Abra o app Sopro para escolher o endereço de $name."

    // ── Confirmação / cancelamento (overlay-only) ────────────────────────
    val cancelledOk = "Tudo bem, cancelei."

    // ── Compras (overlay-only) ───────────────────────────────────────────
    val couldNotSaveNow = "Não consegui salvar agora. Tente de novo."
    val marketNameRepeat = "Não peguei bem — pode falar só o nome do mercado?"
    val noMarketYet =
        "Ainda não tenho nenhum mercado salvo. Quer que eu crie um agora, ou prefere fazer isso pelo app?"
    // [names] e [items] já vêm formatados (humanJoin) do call site.
    fun whichMarket(names: String, items: String) =
        "Você tem $names salvos — em qual eu coloco $items?"
    val addToListWhat = "O que você quer adicionar à lista?"

    // ── Plano (resumo agregado) ──────────────────────────────────────────
    // [FONTE UNICA]
    val couldNotFinishRetry get() = VoiceContent.persona("couldNotFinishRetry")
    // [FONTE UNICA]
    fun partialFailure(failed: Int) =
        VoiceContent.persona("partialFailure").replace("{failed}", failed.toString())
    val done = "Pronto!"
}
