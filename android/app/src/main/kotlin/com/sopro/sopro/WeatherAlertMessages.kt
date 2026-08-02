package com.sopro.sopro

// Mensagens aprovadas dos alertas inteligentes de clima. Cada categoria é uma
// lista — o WeatherAlertEngine sorteia uma a cada disparo (list.random()) para
// variar o texto entre execuções. Os %d/%s/%f são preenchidos com os valores
// reais via String.format (Locale pt-BR) no momento do envio.
object WeatherAlertMessages {
    val umbrella = listOf(
        "Alta chance de chuva hoje (%d%%) — não esquece o guarda-chuva ao sair.",
        "O céu tá armando pra chover (%d%% de chance) — leva uma proteção extra hoje.",
        "%d%% de chance de chuva mais tarde. Guarda-chuva na mochila, só por garantia."
    )
    val rainStarted = listOf(
        "O tempo virou — começou a chover (ou deve começar em breve) em %s.",
        "Ó, olha só, o tempo mudou de ideia: chuva chegando em %s.",
        "Atualização do tempo: chuva prevista pra agora em %s."
    )
    val rainVolume = listOf(
        "Chuva mais forte prevista hoje (%.1fmm) — cuidado com alagamentos no seu trajeto.",
        "Vem chuva de peso hoje — se puder, evita sair na pior hora."
    )
    val severeWeather = listOf(
        "⚠️ Alerta: tempo severo previsto em %s — %s. Evite áreas de risco.",
        "⚠️ Atenção: condições de tempo severo se aproximando. Fique atento e se proteja."
    )
    val hydration = listOf(
        "O ar tá bem seco hoje (%d%%) — bebe mais água que o normal.",
        "Umidade baixa hoje (%d%%) — seu corpo agradece uns golinhos extras de água."
    )
    val extremeHeat = listOf(
        "Vai esquentar de verdade hoje (%.0f°C) — hidrate-se e evite o sol nas horas mais quentes.",
        "%.0f°C hoje — calorão daqueles. Água por perto e sombra sempre que der."
    )

    // BLOCO 2 — vento/chuva severos. %.0f = rajada em km/h (vento) ou mm/h (chuva).
    // Amarelo: aviso; Vermelho: alerta forte (canal severo, som de alarme).
    val strongWindYellow = listOf(
        "Vento forte agora — rajadas de ~%.0f km/h. Cuidado com objetos soltos e ao dirigir.",
        "Rajadas de ~%.0f km/h por aí — segura o que puder voar e atenção na rua."
    )
    val strongWindRed = listOf(
        "⚠️ Vento MUITO forte — rajadas de ~%.0f km/h. Evite sair e afaste-se de árvores e estruturas frágeis.",
        "⚠️ Alerta de vendaval — rajadas de ~%.0f km/h. Fique em local seguro e longe de janelas."
    )
    val heavyRainYellow = listOf(
        "Chuva forte agora (~%.0f mm/h) — risco de alagamento, redobre a atenção no trajeto.",
        "Chovendo pesado (~%.0f mm/h) — evite pontos baixos e dirija com cuidado."
    )
    val heavyRainRed = listOf(
        "⚠️ Chuva MUITO intensa (~%.0f mm/h) — risco alto de alagamento e transtornos. Evite deslocamentos.",
        "⚠️ Temporal em curso (~%.0f mm/h) — procure abrigo e não enfrente vias alagadas."
    )
}
