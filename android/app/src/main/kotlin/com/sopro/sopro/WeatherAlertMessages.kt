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
}
