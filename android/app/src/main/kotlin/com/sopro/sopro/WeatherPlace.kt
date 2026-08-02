package com.sopro.sopro

import android.content.Context
import com.sopro.sopro.logging.Logger
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// Rótulo "Bairro, Cidade" das coordenadas para as notificações nativas de clima.
//
// Híbrido (paridade com o card Dart): lê flutter.last_known_place primeiro — o
// MESMO valor que o card grava via GeocodingRepository.placeLabel. Se vazio, faz
// reverse geocode nativo no Photon (sem API key) e GRAVA de volta em
// flutter.last_known_place, mantendo card + notificação sincronizados. Corrige o
// nome que o OWM erra (rotula pela estação mais próxima: "Praia Grande" vinha
// como "Mongaguá"). Mesmo padrão HTTP direto já usado pro OWM/Gemini/Groq nativos.
object WeatherPlace {

    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_PLACE     = "flutter.last_known_place"

    // Devolve o rótulo do local. [fallback] (nome do OWM) é usado só se o cache
    // estiver vazio E o reverse do Photon falhar.
    fun resolveLabel(
        context: Context, lat: Double, lon: Double, fallback: String, corrId: String
    ): String {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val cached = prefs.getString(KEY_PLACE, null)
        if (!cached.isNullOrEmpty()) return cached

        val label = photonReverse(lat, lon, corrId)
        if (label.isNotEmpty()) {
            prefs.edit().putString(KEY_PLACE, label).apply()
            return label
        }
        return fallback
    }

    // GET photon.komoot.io/reverse → "Bairro, Cidade" (ou só Cidade). "" em falha.
    private fun photonReverse(lat: Double, lon: Double, corrId: String): String {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("https://photon.komoot.io/reverse?lat=$lat&lon=$lon&limit=1")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5_000
                readTimeout = 5_000
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "Sopro/1.0")
            }
            if (conn.responseCode != 200) return ""
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val features = JSONObject(body).optJSONArray("features") ?: return ""
            if (features.length() == 0) return ""
            val props = features.getJSONObject(0).optJSONObject("properties") ?: return ""
            // Mesma cascata de chaves do _photonReverse Dart.
            val city = props.optString(
                "city", props.optString("town", props.optString("locality", "")))
            val district = props.optString(
                "district", props.optString("suburb", props.optString("neighbourhood", "")))
            when {
                city.isEmpty()        -> ""
                district.isNotEmpty() -> "$district, $city"
                else                  -> city
            }
        } catch (e: Exception) {
            Logger.warn("weather_place_reverse_failed", feature = "weather",
                action = "photonReverse", correlationId = corrId,
                payload = mapOf("error" to (e.message ?: "")))
            ""
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }
}
