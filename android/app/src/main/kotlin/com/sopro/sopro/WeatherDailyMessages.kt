package com.sopro.sopro

import java.util.Locale

// Monta o corpo RICO da notificação diária de clima (WeatherNotificationReceiver).
//
// Substitui o corpo cru ("$temp°C, $description") por uma mensagem natural:
// saudação por horário + núcleo (temp/descrição + mínima/máxima) + uma dica por
// categoria de clima (chuva/calor/frio/seco/tranquilo) + despedida. 2-3 variações
// por trecho pra não repetir sempre a mesma frase — mesmo espírito de
// naturalização da persona Dart (BehaviorEngine._greeting/_pick).
//
// NÃO é usado pelo motor adaptativo (WeatherAlertEngine) — só na diária simples.
object WeatherDailyMessages {

    private val ptBr = Locale("pt", "BR")

    // Faixas de horário iguais às do _greeting/_toneOpener do Dart.
    private fun greeting(hour: Int): String = when {
        hour in 5..11  -> listOf("Bom dia!", "Oi, bom dia!", "Bom dia por aí!")
        hour in 12..18 -> listOf("Boa tarde!", "Oi, boa tarde!", "Boa tarde por aí!")
        else           -> listOf("Boa noite!", "Oi, boa noite!", "Boa noite por aí!")
    }.random()

    private fun farewell(hour: Int): String = when {
        hour in 5..11  -> listOf("Tenha um ótimo dia!", "Bom dia e até mais!")
        hour in 12..18 -> listOf("Tenha uma ótima tarde!", "Boa tarde e se cuida!")
        else           -> listOf("Boa noite!", "Descansa bem!")
    }.random()

    // Núcleo: temperatura + descrição, com a faixa min/máx quando disponível
    // (min != max; se o forecast falhou, min==max==temp e omitimos a faixa).
    private fun core(temp: Int, min: Int, max: Int, description: String): String {
        if (min == max) {
            return listOf(
                "Agora $temp°C, $description.",
                "Tá fazendo $temp°C, $description.",
                "$temp°C agora, $description.",
            ).random()
        }
        return listOf(
            "Agora $temp°C, $description. Mínima de $min° e máxima de $max° hoje.",
            "Tá fazendo $temp°C, $description. Hoje varia de $min° a $max°.",
            "$temp°C agora, $description. A previsão vai de $min° a $max° hoje.",
        ).random()
    }

    // Uma dica conforme a condição dominante (ordem de prioridade: chuva → calor →
    // frio → ar seco → tranquilo). %d de umidade formatado com Locale pt-BR.
    private fun advice(
        temp: Int, humidity: Int, condition: String, pop: Int
    ): String {
        val cond = condition.lowercase(ptBr)
        val rainy = cond.contains("rain") || cond.contains("drizzle") ||
            cond.contains("thunder") || pop >= 60
        return when {
            rainy -> listOf(
                "Leva o guarda-chuva, tem chance de chuva.",
                "Vai chover — não esquece a proteção ao sair.",
                "Chuva à vista, melhor sair prevenido.",
            ).random()
            temp >= 32 -> listOf(
                "Calor forte hoje, capricha na água.",
                "Vai esquentar — se hidrata bem e foge do sol do meio-dia.",
            ).random()
            temp <= 15 -> listOf(
                "Tá frio, leva um casaco.",
                "Friozinho hoje, se agasalha bem.",
            ).random()
            humidity in 1..39 -> listOf(
                String.format(ptBr, "Ar seco (%d%%), bebe bastante água.", humidity),
                String.format(ptBr, "Umidade baixa (%d%%), hidrata bem hoje.", humidity),
            ).random()
            else -> listOf(
                "Tempo tranquilo por aí.",
                "Dia bom pra resolver as coisas.",
                "Clima ok pra sair.",
            ).random()
        }
    }

    // Monta a mensagem completa. [pop] = chance de chuva em % (0 quando ausente).
    fun build(
        temp: Int, min: Int, max: Int, humidity: Int,
        condition: String, description: String, pop: Int, hour: Int
    ): String {
        val g = greeting(hour)
        val c = core(temp, min, max, description)
        val a = advice(temp, humidity, condition, pop)
        val f = farewell(hour)
        return "$g $c $a $f"
    }
}
