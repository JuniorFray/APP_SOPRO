package com.sopro.sopro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.SessionManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

// Notificação diária de clima — disparada pelo AlarmManager (app fechado/morto),
// independente do Flutter Engine. Lê coords + chave OWM das SharedPreferences do
// Flutter, chama a API direto (HttpURLConnection) e reagenda pra amanhã.
class WeatherNotificationReceiver : BroadcastReceiver() {

    companion object {
        // Reaproveita o canal IMPORTANCE_MAX das notificações de trigger.
        private const val CHANNEL_ID   = "sopro_triggers"
        private const val CHANNEL_NAME = "Sopro — Gatilhos"

        private const val PREFS        = "FlutterSharedPreferences"
        private const val KEY_LAT      = "flutter.last_known_lat"
        private const val KEY_LON      = "flutter.last_known_lon"
        private const val KEY_API      = "flutter.openweather_api_key"
        private const val KEY_ENABLED  = "flutter.weather_notification_enabled"
        private const val KEY_HOUR     = "flutter.weather_notification_hour"
        private const val KEY_MINUTE   = "flutter.weather_notification_minute"

        // Prefixo que o shared_preferences usa ao serializar Double como String
        // (algumas versões). O leitor tolerante abaixo cobre todos os formatos.
        private const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"
    }

    override fun onReceive(context: Context, intent: Intent) {
        SessionManager.init(context)
        val start = System.currentTimeMillis()
        val corrId = CorrelationManager.beginOperation("weather_notification")

        val pendingResult = goAsync()
        Executors.newSingleThreadExecutor().execute {
            try {
                process(context, corrId)
                Logger.info("receiver_finished", feature = "weather", action = "onReceive",
                    correlationId = corrId, durationMs = System.currentTimeMillis() - start)
            } catch (e: Exception) {
                Logger.error("weather_notification_failed", feature = "weather",
                    action = "onReceive", correlationId = corrId, exception = e)
            } finally {
                CorrelationManager.endOperation("weather_notification")
                pendingResult.finish()
            }
        }
    }

    private fun process(context: Context, corrId: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Reagenda pra amanhã ANTES de qualquer coisa: mesmo que a chamada de
        // rede falhe, a notificação diária continua nos próximos dias.
        if (prefs.getBoolean(KEY_ENABLED, false)) {
            val hour = prefs.getLong(KEY_HOUR, 8L).toInt()
            val minute = prefs.getLong(KEY_MINUTE, 0L).toInt()
            WeatherNotificationScheduler.schedule(context, hour, minute)
        }

        val lat = readFlutterDouble(prefs, KEY_LAT)
        val lon = readFlutterDouble(prefs, KEY_LON)
        val apiKey = prefs.getString(KEY_API, null)

        if (lat == null || lon == null || (lat == 0.0 && lon == 0.0) || apiKey.isNullOrEmpty()) {
            Logger.info("weather_skip_no_data", feature = "weather", action = "process",
                correlationId = corrId,
                payload = mapOf("has_coords" to (lat != null && lon != null).toString(),
                    "has_key" to (!apiKey.isNullOrEmpty()).toString()))
            return
        }

        val weather = fetchWeather(lat, lon, apiKey, corrId) ?: return
        showNotification(context, weather.city, weather.temp, weather.description, corrId)
    }

    private data class WeatherNow(val city: String, val temp: Int, val description: String)

    // GET direto na OWM (mesmo padrão de logToSupabase em BootReceiver). Retorna
    // null em qualquer falha — o receiver apenas não notifica.
    private fun fetchWeather(lat: Double, lon: Double, apiKey: String, corrId: String): WeatherNow? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("https://api.openweathermap.org/data/2.5/weather" +
                "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8_000
                readTimeout = 8_000
                setRequestProperty("Accept", "application/json")
            }
            if (conn.responseCode != 200) {
                Logger.warn("weather_fetch_http_error", feature = "weather", action = "fetchWeather",
                    correlationId = corrId, payload = mapOf("http" to conn.responseCode.toString()))
                return null
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val main = json.getJSONObject("main")
            val weatherArr = json.getJSONArray("weather")
            val w0 = weatherArr.getJSONObject(0)
            WeatherNow(
                city = json.optString("name", ""),
                temp = Math.round(main.getDouble("temp")).toInt(),
                description = w0.optString("description", ""),
            )
        } catch (e: Exception) {
            Logger.warn("weather_fetch_exception", feature = "weather", action = "fetchWeather",
                correlationId = corrId, payload = mapOf("error" to (e.message ?: "")))
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    private fun showNotification(
        context: Context, city: String, temp: Int, description: String, corrId: String
    ) {
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            Logger.warn("notification_permission_denied", feature = "weather",
                action = "showNotification", correlationId = corrId)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_MAX
                ).apply {
                    enableVibration(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(channel)
            }
        }

        val where = if (city.isNotEmpty()) " em $city" else ""
        val body  = "$temp°C, $description".trimEnd(',', ' ')

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Tempo hoje$where")
            .setContentText(body)
            .setTicker("Previsão do dia")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .build()

        try {
            nmCompat.notify(WeatherNotificationScheduler.NOTIF_ID, notification)
            Logger.info("weather_notification_sent", feature = "weather", action = "showNotification",
                correlationId = corrId,
                payload = mapOf("city" to city, "temp" to temp.toString()))
        } catch (e: SecurityException) {
            Logger.error("weather_notification_post_failed", feature = "weather",
                action = "showNotification", correlationId = corrId, exception = e)
        }
    }

    // Lê um double gravado pelo shared_preferences (Flutter) tolerando qualquer
    // encoding: Long (rawBits), Float, Double, Int ou String (com/sem prefixo).
    private fun readFlutterDouble(prefs: SharedPreferences, key: String): Double? {
        val raw = prefs.all[key] ?: return null
        return when (raw) {
            is Double -> raw
            is Float  -> raw.toDouble()
            is Long   -> java.lang.Double.longBitsToDouble(raw) // shared_preferences grava double como rawBits
            is Int    -> raw.toDouble()
            is String -> {
                val s = if (raw.startsWith(DOUBLE_PREFIX)) raw.substring(DOUBLE_PREFIX.length) else raw
                s.toDoubleOrNull()
            }
            else -> null
        }
    }
}
