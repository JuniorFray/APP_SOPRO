package com.sopro.sopro

import android.content.Context
import android.location.Location
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.random.Random

// OverlayWeather — responde clima/tempo no overlay (app fechado), sem Flutter
// Engine. Espelha a WeatherQuerySkill + a fala de clima da AssistantPersona
// (behavior_engine.dart) do Home: resolve local, consulta a OpenWeatherMap
// nativamente (mesmo endpoint/chave já usados pelo WeatherAlertEngine) e monta a
// fala variada em pt-BR. Geração de fala é lógica → implementação própria por
// plataforma (como previsto na unificação).
object OverlayWeather {

    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_API = "flutter.openweather_api_key"

    // Frases de erro — mesmas do Home (persona.weather*). Locais ao overlay porque
    // a geração conversacional de clima é específica de plataforma.
    private const val NO_LOCATION = "Ainda não sei sua localização pra checar o tempo."
    private const val PLACE_NOT_FOUND = "Não encontrei esse lugar pra ver o tempo."
    private const val ERROR = "Não consegui checar o tempo agora."

    // Ponto de entrada: devolve a FRASE a ser falada (clima ou erro).
    // [locProvider] resolve o GPS/last_known atual (só usado quando place == null).
    fun answer(
        context: Context,
        place: String?,
        scope: String,
        locProvider: () -> Location?,
    ): String {
        val corrId = CorrelationManager.correlationIdFor("voice")

        // ── Coordenadas do alvo ──────────────────────────────────────────────
        val lat: Double
        val lon: Double
        var placeLabel: String? = null
        if (place != null) {
            val geo = forwardGeocode(place, corrId) ?: return PLACE_NOT_FOUND
            lat = geo.first; lon = geo.second; placeLabel = geo.third
        } else {
            val loc = locProvider() ?: return NO_LOCATION
            lat = loc.latitude; lon = loc.longitude
        }

        val apiKey = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_API, null) ?: return ERROR
        if (apiKey.isEmpty()) return ERROR

        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

        return try {
            if (scope == "week" || scope == "semana" || scope == "forecast") {
                val days = fetchForecastDays(lat, lon, apiKey, corrId)
                if (days.isEmpty()) ERROR
                else weatherForecast(days, hour, placeLabel)
            } else {
                val current = fetchJson(
                    "https://api.openweathermap.org/data/2.5/weather" +
                        "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br", corrId)
                    ?: return ERROR
                val main = current.getJSONObject("main")
                val w0 = current.getJSONArray("weather").getJSONObject(0)
                val temp = main.getDouble("temp")
                val humidity = main.optInt("humidity", 0)
                val condition = w0.optString("main", "")
                val description = w0.optString("description", "")
                // pop do período mais próximo (0..1 → %). Não-fatal.
                val pop = try {
                    fetchJson(
                        "https://api.openweathermap.org/data/2.5/forecast" +
                            "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br", corrId)
                        ?.optJSONArray("list")?.optJSONObject(0)
                        ?.optDouble("pop", 0.0)?.let { (it * 100).toInt() }
                } catch (e: Exception) { null }
                weatherNow(temp, description, condition, humidity, pop, hour, placeLabel)
            }
        } catch (e: Exception) {
            Logger.warn("weather_query_failed", feature = "floating_voice",
                action = "weather", payload = mapOf("error" to (e.message ?: "")),
                correlationId = corrId)
            ERROR
        }
    }

    // ── Fala do clima ATUAL (port da persona.weatherNow, com variação sorteada) ──
    private fun weatherNow(
        temp: Double, description: String, condition: String,
        humidity: Int?, popPercent: Int?, hour: Int, place: String?,
    ): String {
        val t = temp.roundToInt()
        val r = Random.Default
        val cond = condition.lowercase()
        val loc = if (!place.isNullOrEmpty()) " em $place" else ""

        val corePool = listOf(
            "agora está $t graus$loc, com $description",
            "tá fazendo $t graus$loc, $description",
            "o tempo$loc está em $t graus, $description",
            "estão $t graus$loc, com $description",
        )
        val lead = pick(r, listOf("", "deixa eu ver... ", "olha só... ", "então... "))
        val core = corePool[r.nextInt(corePool.size)]
        var msg = greeting(hour, r) + if (lead.isEmpty()) capFirst(core) else capFirst(lead) + core

        val p = popPercent ?: 0
        val rainy = cond.contains("rain") || cond.contains("thunder") || cond.contains("drizzle")
        if (p >= 60 || rainy) {
            msg += pick(r, listOf(
                ". Alta chance de chuva${if (p > 0) " ($p%)" else ""}, leva o guarda-chuva",
                ". Vai chover${if (p > 0) " ($p% de chance)" else ""}, não esquece o guarda-chuva",
                ". Tempo de chuva${if (p > 0) " ($p%)" else ""}, melhor sair prevenido",
            ))
        } else if (p >= 30) {
            msg += pick(r, listOf(
                ". Pode pintar uma chuva ($p%), vale levar guarda-chuva",
                ". Chance média de chuva ($p%)",
            ))
        } else if (p > 0) {
            msg += ". Baixa chance de chuva ($p%)"
        } else if (r.nextBoolean()) {
            msg += ". Sem chuva à vista"
        }

        val clearDay = cond.contains("clear") && hour in 6..17
        if (t >= 32) {
            msg += pick(r, listOf(". Tá quente, bebe bastante água", ". Calorão, se hidrata bem"))
            if (clearDay) {
                msg += pick(r, listOf(" e capricha no protetor solar", ". E cuidado com o sol"))
            }
        } else if (clearDay && t >= 26) {
            msg += pick(r, listOf(
                ". Sol forte, não esquece o protetor",
                ". Bastante sol lá fora, se protege dele",
            ))
        } else if (t <= 15) {
            msg += pick(r, listOf(". Tá frio, leva um casaco", ". Friozinho, se agasalha"))
        } else if (humidity != null && humidity >= 85) {
            msg += ". O ar está bem úmido"
        }

        return "$msg."
    }

    // Dia da previsão (rótulo + min/max + condição em pt-BR).
    private data class ForecastDay(val label: String, val min: Int, val max: Int, val cond: String)

    // ── Fala da PREVISÃO (port da persona.weatherForecast) ──────────────────────
    private fun weatherForecast(days: List<ForecastDay>, hour: Int, place: String?): String {
        if (days.isEmpty()) return ERROR
        val r = Random.Default
        val loc = if (!place.isNullOrEmpty()) " para $place" else ""
        val intro = pick(r, listOf(
            "Previsão$loc pros próximos dias: ",
            "Olha a previsão$loc: ",
            "Nos próximos dias$loc: ",
        ))
        val parts = days.joinToString("; ") {
            "${it.label}, de ${it.min} a ${it.max} graus, ${it.cond}"
        }
        return "${greeting(hour, r)}$intro$parts."
    }

    // Agrega o /forecast 3-horário em dias (pula hoje), até 4 dias.
    private fun fetchForecastDays(lat: Double, lon: Double, apiKey: String, corrId: String?): List<ForecastDay> {
        val forecast = fetchJson(
            "https://api.openweathermap.org/data/2.5/forecast" +
                "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br", corrId) ?: return emptyList()
        val list = forecast.optJSONArray("list") ?: return emptyList()

        // min/max do dia + condição do período mais próximo do meio-dia.
        class Agg(var min: Double, var max: Double, var cond: String, var bestHourDist: Int)
        val byDay = LinkedHashMap<String, Agg>()
        val todayKey = dateKey(Calendar.getInstance())

        for (i in 0 until list.length()) {
            val item = list.optJSONObject(i) ?: continue
            val cal = Calendar.getInstance().apply { timeInMillis = item.getLong("dt") * 1000L }
            val key = dateKey(cal)
            if (key == todayKey) continue // previsão = próximos dias
            val main = item.getJSONObject("main")
            val tmin = main.getDouble("temp_min")
            val tmax = main.getDouble("temp_max")
            val cond = item.getJSONArray("weather").getJSONObject(0).optString("main", "")
            val hourDist = abs(cal.get(Calendar.HOUR_OF_DAY) - 12)
            val agg = byDay[key]
            if (agg == null) {
                byDay[key] = Agg(tmin, tmax, cond, hourDist)
            } else {
                if (tmin < agg.min) agg.min = tmin
                if (tmax > agg.max) agg.max = tmax
                if (hourDist < agg.bestHourDist) { agg.cond = cond; agg.bestHourDist = hourDist }
            }
        }

        return byDay.entries.take(4).map { (key, a) ->
            ForecastDay(weekdayLabel(key), a.min.roundToInt(), a.max.roundToInt(), condPt(a.cond))
        }
    }

    // Geocoding forward (Photon/OSM) — o overlay não tem geocoder próprio; usa o
    // mesmo provedor gratuito do fallback Dart. Retorna (lat, lon, rótulo).
    private fun forwardGeocode(place: String, corrId: String?): Triple<Double, Double, String>? {
        val q = URLEncoder.encode(place, "UTF-8")
        val json = fetchJson("https://photon.komoot.io/api/?q=$q&limit=1&lang=pt", corrId) ?: return null
        val features = json.optJSONArray("features") ?: return null
        if (features.length() == 0) return null
        val f = features.getJSONObject(0)
        val coords = f.getJSONObject("geometry").getJSONArray("coordinates") // [lon, lat]
        val lon = coords.getDouble(0)
        val lat = coords.getDouble(1)
        val props = f.optJSONObject("properties")
        val label = props?.optString("city", "")?.takeIf { it.isNotEmpty() }
            ?: props?.optString("name", "")?.takeIf { it.isNotEmpty() }
            ?: place
        return Triple(lat, lon, label)
    }

    // GET simples com timeout, devolve JSON ou null (qualquer falha).
    private fun fetchJson(urlStr: String, corrId: String?): JSONObject? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 6000
                readTimeout = 6000
                setRequestProperty("User-Agent", "Sopro/1.0")
            }
            if (conn.responseCode != 200) return null
            JSONObject(conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() })
        } catch (e: Exception) {
            Logger.warn("weather_fetch_failed", feature = "floating_voice", action = "weather",
                payload = mapOf("error" to (e.message ?: "")), correlationId = corrId)
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    // ── Helpers de fala (port dos helpers da persona) ───────────────────────────

    private fun greeting(hour: Int, r: Random): String {
        val pool = when {
            hour < 12 -> listOf("Bom dia! ", "Oi, bom dia! ", "Opa! ")
            hour < 18 -> listOf("Boa tarde! ", "Oi! ", "Opa, boa tarde! ")
            else -> listOf("Boa noite! ", "Oi! ", "Opa! ")
        }
        return pool[r.nextInt(pool.size)]
    }

    private fun pick(r: Random, options: List<String>): String = options[r.nextInt(options.size)]

    private fun capFirst(s: String): String =
        if (s.isEmpty()) s else s.substring(0, 1).uppercase(Locale("pt", "BR")) + s.substring(1)

    // Condição "main" do OpenWeather (inglês) → pt-BR na fala da previsão.
    private fun condPt(condition: String): String = when (condition.lowercase()) {
        "clear" -> "céu limpo"
        "clouds" -> "nublado"
        "rain" -> "chuva"
        "drizzle" -> "garoa"
        "thunderstorm" -> "tempestade"
        "snow" -> "neve"
        "mist", "fog" -> "neblina"
        "haze" -> "névoa"
        else -> condition.lowercase()
    }

    // "yyyy-MM-dd" a partir de um Calendar (para agrupar dias).
    private fun dateKey(cal: Calendar): String = String.format(
        Locale.US, "%04d-%02d-%02d",
        cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    // Rótulo pt-BR do dia da semana a partir de "yyyy-MM-dd".
    private fun weekdayLabel(key: String): String {
        val names = listOf("segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo")
        return try {
            val p = key.split("-").map { it.toInt() }
            val cal = Calendar.getInstance().apply { set(p[0], p[1] - 1, p[2], 12, 0, 0) }
            val dow = cal.get(Calendar.DAY_OF_WEEK) // 1=Dom..7=Sáb
            val iso = if (dow == Calendar.SUNDAY) 7 else dow - 1 // 1=Seg..7=Dom
            names[iso - 1]
        } catch (e: Exception) {
            key
        }
    }
}
