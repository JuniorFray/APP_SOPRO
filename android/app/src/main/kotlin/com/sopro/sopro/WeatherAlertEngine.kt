package com.sopro.sopro

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.SessionManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

// ─────────────────────────────────────────────────────────────────────────────
// Motor adaptativo de alertas inteligentes de clima.
//
// Mecanismo SEPARADO da notificação diária (WeatherNotificationReceiver): faz
// checagens periódicas ao longo do dia (intervalo adaptativo 1h/3h) e dispara
// avisos por categoria (guarda-chuva, chuva começando, volume de chuva, tempo
// severo, hidratação, calor extremo) — cada um com anti-spam próprio.
//
// Independente do Flutter Engine: lê coords + chave OWM das SharedPreferences do
// Flutter, chama a API via HttpURLConnection e se reagenda via AlarmManager.
// Mesma filosofia do WeatherNotificationScheduler: reagenda ANTES da rede (um
// fallback de 3h) para nunca travar o ciclo, e de novo no fim com o intervalo
// decidido.
// ─────────────────────────────────────────────────────────────────────────────

// Agenda/cancela o alarme único do motor. requestCode fixo → reagendar sobrescreve.
object WeatherAlertScheduler {

    private fun requestCode(): Int = "weather_alert_engine".hashCode() and 0x7FFFFFFF

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    private fun pendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, requestCode(),
            Intent(context, WeatherAlertReceiver::class.java),
            pendingIntentFlags())

    // Agenda a próxima checagem para daqui a [delayMs] milissegundos.
    fun scheduleIn(context: Context, delayMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val at = System.currentTimeMillis() + delayMs
        val pi = pendingIntent(context)
        // Alertas não precisam de exatidão: se o exact-alarm foi revogado, cai no
        // inexato (setAndAllowWhileIdle) para MANTER o ciclo vivo mesmo assim.
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            am.canScheduleExactAlarms()
        if (canExact) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
        Logger.info("weather_alert_scheduled", feature = "weather_alerts", action = "scheduleIn",
            payload = mapOf("delay_ms" to delayMs.toString(), "next_at_ms" to at.toString(),
                "exact" to canExact.toString()))
    }

    // Primeira checagem após ligar/reboot: daqui a poucos minutos.
    fun scheduleFirst(context: Context) = scheduleIn(context, WeatherAlertEngine.FIRST_DELAY_MS)

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context))
        Logger.info("weather_alert_cancelled", feature = "weather_alerts", action = "cancel")
    }
}

// BroadcastReceiver acionado pelo AlarmManager. Roda a checagem fora do main
// thread (goAsync) e delega a lógica ao WeatherAlertEngine.
class WeatherAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        SessionManager.init(context)
        val start = System.currentTimeMillis()
        val corrId = CorrelationManager.beginOperation("weather_alert")

        val pendingResult = goAsync()
        Executors.newSingleThreadExecutor().execute {
            try {
                WeatherAlertEngine.runCheck(context, corrId)
                Logger.info("receiver_finished", feature = "weather_alerts", action = "onReceive",
                    correlationId = corrId, durationMs = System.currentTimeMillis() - start)
            } catch (e: Exception) {
                Logger.error("weather_alert_failed", feature = "weather_alerts",
                    action = "onReceive", correlationId = corrId, exception = e)
            } finally {
                CorrelationManager.endOperation("weather_alert")
                pendingResult.finish()
            }
        }
    }
}

object WeatherAlertEngine {

    // ── Prefs do Flutter (coords + chave + enabled) ──────────────────────────
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_LAT     = "flutter.last_known_lat"
    private const val KEY_LON     = "flutter.last_known_lon"
    private const val KEY_API     = "flutter.openweather_api_key"
    private const val KEY_ENABLED = "flutter.weather_alerts_enabled"
    private const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

    // ── Prefs de estado do motor (só nativo) ─────────────────────────────────
    private const val ENGINE_PREFS = "sopro_weather_alerts"
    private const val PREV_CONDITION = "weather_alert_prev_condition"
    private const val PREV_POP       = "weather_alert_prev_pop"
    private const val PREV_TEMP      = "weather_alert_prev_temp"
    private const val PREV_SEVERE    = "weather_alert_prev_severe"
    private const val PREV_CHECK_AT  = "weather_alert_prev_check_at"
    private const val LAST_UMBRELLA  = "weather_alert_last_umbrella_at"
    private const val LAST_RAIN      = "weather_alert_last_rain_at"
    private const val LAST_VOLUME    = "weather_alert_last_volume_at"
    private const val LAST_SEVERE    = "weather_alert_last_severe_at"
    private const val LAST_HYDRATION = "weather_alert_last_hydration_at"
    private const val LAST_HEAT      = "weather_alert_last_heat_at"
    private const val LAST_WIND_RAIN_Y = "weather_alert_last_wind_rain_y_at"
    private const val LAST_WIND_RAIN_R = "weather_alert_last_wind_rain_r_at"

    // ── Canais de notificação ────────────────────────────────────────────────
    private const val CHANNEL_ID     = "sopro_triggers"          // canal normal (IMPORTANCE_MAX)
    private const val CHANNEL_NAME   = "Sopro — Gatilhos"
    private const val SEVERE_CHANNEL = "sopro_weather_severe"    // canal próprio, mais chamativo
    private const val SEVERE_NAME    = "Sopro — Tempo severo"

    // ── Notif IDs distintos por categoria (não se sobrescrevem) ──────────────
    private const val ID_UMBRELLA  = 0x5751
    private const val ID_RAIN      = 0x5752
    private const val ID_VOLUME    = 0x5753
    private const val ID_SEVERE    = 0x5754
    private const val ID_HYDRATION = 0x5755
    private const val ID_HEAT      = 0x5756
    private const val ID_WIND_RAIN_Y = 0x5757  // chuva/vento forte (amarelo)
    private const val ID_WIND_RAIN_R = 0x5758  // chuva/vento severo (vermelho)

    // ── Intervalos e limiares ────────────────────────────────────────────────
    const val FIRST_DELAY_MS = 5L * 60L * 1000L          // primeira checagem (+5min)
    private const val INTERVAL_NOTABLE_MS = 60L * 60L * 1000L      // 1h
    private const val INTERVAL_STABLE_MS  = 3L * 60L * 60L * 1000L // 3h
    private const val COOLDOWN_8H  = 8L * 60L * 60L * 1000L
    private const val COOLDOWN_12H = 12L * 60L * 60L * 1000L

    private const val POP_THRESHOLD    = 30      // % de chance de chuva "relevante"
    private const val RAIN_MM_THRESHOLD = 4.0    // mm em rain.1h/3h para volume alto
    // BLOCO 2 — chuva/vento SEVEROS (rain.1h em mm/h, wind.gust em m/s). Amarelo
    // ~60km/h ou 20mm/h; vermelho ~80km/h ou 45mm/h. rain_volume (4mm) fica capado
    // ABAIXO do amarelo (4–20mm) pra não duplicar alerta no mesmo evento de chuva.
    private const val RAIN_YELLOW_MM = 20.0   // ≥20 mm/h = chuva forte (amarelo)
    private const val RAIN_RED_MM    = 45.0   // ≥45 mm/h = chuva muito intensa (vermelho)
    private const val GUST_YELLOW_MS = 16.7   // >~60 km/h (amarelo)
    private const val GUST_RED_MS    = 22.2   // >~80 km/h (vermelho)
    private const val HUMIDITY_LOW      = 50     // umidade < 50% = ar seco
    private const val HEAT_THRESHOLD    = 33.0   // temp > 33°C = calor extremo
    private const val NOTABLE_POP_JUMP  = 30     // salto de pop (pts) = mudança notável
    private const val NOTABLE_TEMP_DELTA = 5.0   // variação de temp (°C) = mudança notável

    private val ptBr = Locale("pt", "BR")

    // Executa UMA checagem: fetch, avalia categorias, notifica, decide intervalo
    // e reagenda. Sempre reagenda (fallback 3h antes da rede).
    fun runCheck(context: Context, corrId: String) {
        val fprefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

        // Desligado enquanto o alarme estava pendente → não reagenda, ciclo morre.
        if (!fprefs.getBoolean(KEY_ENABLED, false)) {
            Logger.info("weather_alert_disabled", feature = "weather_alerts",
                action = "runCheck", correlationId = corrId)
            return
        }

        // Fallback ANTES da rede: garante o próximo ciclo mesmo se a chamada falhar.
        WeatherAlertScheduler.scheduleIn(context, INTERVAL_STABLE_MS)

        val lat = readFlutterDouble(fprefs, KEY_LAT)
        val lon = readFlutterDouble(fprefs, KEY_LON)
        val apiKey = fprefs.getString(KEY_API, null)
        if (lat == null || lon == null || (lat == 0.0 && lon == 0.0) || apiKey.isNullOrEmpty()) {
            Logger.info("weather_alert_skip_no_data", feature = "weather_alerts",
                action = "runCheck", correlationId = corrId)
            return  // fallback de 3h já agendado
        }

        val current = fetchJson(
            "https://api.openweathermap.org/data/2.5/weather" +
                "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br", corrId) ?: return
        val forecast = fetchJson(
            "https://api.openweathermap.org/data/2.5/forecast" +
                "?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=pt_br", corrId)

        // ── Extrai leitura atual ─────────────────────────────────────────────
        val main = current.getJSONObject("main")
        val w0 = current.getJSONArray("weather").getJSONObject(0)
        val temp = main.getDouble("temp")
        val humidity = main.getInt("humidity")
        val condition = w0.optString("main", "")
        val weatherId = w0.optInt("id", 0)
        val description = w0.optString("description", "")
        // Cidade certa (híbrido cache Dart → Photon reverse). name do OWM é fallback.
        val city = WeatherPlace.resolveLabel(context, lat, lon, current.optString("name", ""), corrId)
        // rain.1h (preferido) ou rain.3h do payload atual, se houver.
        val rainVol = current.optJSONObject("rain")?.let {
            it.optDouble("1h", it.optDouble("3h", 0.0))
        } ?: 0.0
        // Rajada de vento (m/s) — condicional no payload, default 0.0 (padrão do rain).
        val gust = current.optJSONObject("wind")?.optDouble("gust", 0.0) ?: 0.0
        // pop do período mais próximo de agora (0..1 → %).
        val popNext = forecast?.optJSONArray("list")?.optJSONObject(0)
            ?.optDouble("pop", 0.0)?.let { (it * 100).toInt() } ?: 0

        val isRainCond = condition == "Rain" || condition == "Drizzle" || condition == "Thunderstorm"
        val isSevere = weatherId in 200..232 ||
            weatherId in intArrayOf(502, 503, 504, 522) || weatherId == 511

        // ── Estado anterior ──────────────────────────────────────────────────
        val eprefs = context.getSharedPreferences(ENGINE_PREFS, Context.MODE_PRIVATE)
        val prevCheckAt = eprefs.getLong(PREV_CHECK_AT, 0L)
        val prevCondition = eprefs.getString(PREV_CONDITION, "") ?: ""
        val prevPop = eprefs.getInt(PREV_POP, 0)
        val prevTemp = eprefs.getFloat(PREV_TEMP, Float.NaN)
        val prevSevere = eprefs.getBoolean(PREV_SEVERE, false)
        val hasPrev = prevCheckAt > 0L

        val now = System.currentTimeMillis()
        val fired = mutableListOf<String>()

        // ── Avalia as 6 categorias (com anti-spam por cooldown) ──────────────
        // Guarda-chuva: chance relevante do próximo período.
        if (popNext >= POP_THRESHOLD && dueAgo(eprefs, LAST_UMBRELLA, now, COOLDOWN_8H)) {
            notify(context, ID_UMBRELLA, CHANNEL_ID, false,
                String.format(ptBr, WeatherAlertMessages.umbrella.random(), popNext), corrId)
            eprefs.edit().putLong(LAST_UMBRELLA, now).apply()
            fired.add("umbrella")
        }
        // Chuva começando: condição virou chuva (não era antes).
        if (isRainCond && (!hasPrev || !isRainMain(prevCondition)) &&
            dueAgo(eprefs, LAST_RAIN, now, COOLDOWN_8H)) {
            notify(context, ID_RAIN, CHANNEL_ID, false,
                String.format(ptBr, WeatherAlertMessages.rainStarted.random(), city), corrId)
            eprefs.edit().putLong(LAST_RAIN, now).apply()
            fired.add("rain_started")
        }
        // Volume de chuva MODERADO (4–20mm): acima de 20mm o alerta severo abaixo
        // assume, evitando alerta duplo pro mesmo evento (cap confirmado no Bloco 2).
        if (rainVol >= RAIN_MM_THRESHOLD && rainVol < RAIN_YELLOW_MM &&
            dueAgo(eprefs, LAST_VOLUME, now, COOLDOWN_8H)) {
            notify(context, ID_VOLUME, CHANNEL_ID, false,
                String.format(ptBr, WeatherAlertMessages.rainVolume.random(), rainVol), corrId)
            eprefs.edit().putLong(LAST_VOLUME, now).apply()
            fired.add("rain_volume")
        }
        // BLOCO 2 — chuva/vento SEVERO (rajada OU volume de chuva). Vermelho tem
        // precedência sobre amarelo (limiares aninhados → só um dispara por evento).
        // Vermelho usa o canal severo (som de alarme); amarelo, o canal normal. A
        // mensagem reflete a causa dominante (vento se rajada estourou, senão chuva).
        val gustKmh = gust * 3.6
        if ((gust > GUST_RED_MS || rainVol >= RAIN_RED_MM) &&
            dueAgo(eprefs, LAST_WIND_RAIN_R, now, COOLDOWN_8H)) {
            val msg = if (gust > GUST_RED_MS)
                String.format(ptBr, WeatherAlertMessages.strongWindRed.random(), gustKmh)
            else
                String.format(ptBr, WeatherAlertMessages.heavyRainRed.random(), rainVol)
            notify(context, ID_WIND_RAIN_R, SEVERE_CHANNEL, true, msg, corrId)
            eprefs.edit().putLong(LAST_WIND_RAIN_R, now).apply()
            fired.add("wind_rain_red")
        } else if ((gust > GUST_YELLOW_MS || rainVol >= RAIN_YELLOW_MM) &&
            dueAgo(eprefs, LAST_WIND_RAIN_Y, now, COOLDOWN_8H)) {
            val msg = if (gust > GUST_YELLOW_MS)
                String.format(ptBr, WeatherAlertMessages.strongWindYellow.random(), gustKmh)
            else
                String.format(ptBr, WeatherAlertMessages.heavyRainYellow.random(), rainVol)
            notify(context, ID_WIND_RAIN_Y, CHANNEL_ID, false, msg, corrId)
            eprefs.edit().putLong(LAST_WIND_RAIN_Y, now).apply()
            fired.add("wind_rain_yellow")
        }
        // Tempo severo → canal próprio (mais chamativo).
        if (isSevere && dueAgo(eprefs, LAST_SEVERE, now, COOLDOWN_8H)) {
            notify(context, ID_SEVERE, SEVERE_CHANNEL, true,
                String.format(ptBr, WeatherAlertMessages.severeWeather.random(), city, description), corrId)
            eprefs.edit().putLong(LAST_SEVERE, now).apply()
            fired.add("severe")
        }
        // Hidratação: ar seco (cooldown maior, 12h).
        if (humidity < HUMIDITY_LOW && dueAgo(eprefs, LAST_HYDRATION, now, COOLDOWN_12H)) {
            notify(context, ID_HYDRATION, CHANNEL_ID, false,
                String.format(ptBr, WeatherAlertMessages.hydration.random(), humidity), corrId)
            eprefs.edit().putLong(LAST_HYDRATION, now).apply()
            fired.add("hydration")
        }
        // Calor extremo.
        if (temp > HEAT_THRESHOLD && dueAgo(eprefs, LAST_HEAT, now, COOLDOWN_8H)) {
            notify(context, ID_HEAT, CHANNEL_ID, false,
                String.format(ptBr, WeatherAlertMessages.extremeHeat.random(), temp), corrId)
            eprefs.edit().putLong(LAST_HEAT, now).apply()
            fired.add("extreme_heat")
        }

        // ── Decide o próximo intervalo (comparando com a checagem anterior) ──
        val notable = hasPrev && (
            condition != prevCondition ||
            (popNext - prevPop) > NOTABLE_POP_JUMP ||
            (isSevere && !prevSevere) ||
            (!prevTemp.isNaN() && Math.abs(temp - prevTemp) > NOTABLE_TEMP_DELTA))
        val nextMs = if (notable) INTERVAL_NOTABLE_MS else INTERVAL_STABLE_MS

        // ── Salva o novo estado para a próxima checagem comparar ─────────────
        eprefs.edit()
            .putString(PREV_CONDITION, condition)
            .putInt(PREV_POP, popNext)
            .putFloat(PREV_TEMP, temp.toFloat())
            .putBoolean(PREV_SEVERE, isSevere)
            .putLong(PREV_CHECK_AT, now)
            .apply()

        // Reagenda com o intervalo decidido (sobrescreve o fallback de 3h).
        WeatherAlertScheduler.scheduleIn(context, nextMs)

        Logger.info("weather_alert_check", feature = "weather_alerts", action = "runCheck",
            correlationId = corrId,
            payload = mapOf(
                "categories_fired" to fired.joinToString(","),
                "next_interval_h" to (nextMs / (60L * 60L * 1000L)).toString(),
                "notable_change" to notable.toString(),
                "pop_next" to popNext.toString(),
                "temp" to temp.toString(),
                "humidity" to humidity.toString(),
                "condition" to condition))
    }

    private fun isRainMain(main: String): Boolean =
        main == "Rain" || main == "Drizzle" || main == "Thunderstorm"

    // true se a categoria não foi alertada nas últimas [cooldownMs] (anti-spam).
    private fun dueAgo(prefs: SharedPreferences, key: String, now: Long, cooldownMs: Long): Boolean =
        now - prefs.getLong(key, 0L) >= cooldownMs

    // GET simples na OWM. Retorna null em qualquer falha (motor apenas não notifica).
    private fun fetchJson(urlStr: String, corrId: String): JSONObject? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8_000
                readTimeout = 8_000
                setRequestProperty("Accept", "application/json")
            }
            if (conn.responseCode != 200) {
                Logger.warn("weather_alert_http_error", feature = "weather_alerts",
                    action = "fetchJson", correlationId = corrId,
                    payload = mapOf("http" to conn.responseCode.toString()))
                return null
            }
            JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        } catch (e: Exception) {
            Logger.warn("weather_alert_fetch_exception", feature = "weather_alerts",
                action = "fetchJson", correlationId = corrId,
                payload = mapOf("error" to (e.message ?: "")))
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    // Envia a notificação no canal indicado. [severe]=true usa o canal próprio
    // (IMPORTANCE_HIGH + som de alarme + vibração), criado sob demanda.
    private fun notify(
        context: Context, notifId: Int, channelId: String, severe: Boolean,
        body: String, corrId: String
    ) {
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            Logger.warn("notification_permission_denied", feature = "weather_alerts",
                action = "notify", correlationId = corrId)
            return
        }
        ensureChannels(context, severe)

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle(if (severe) "Sopro Clima — Alerta" else "Sopro Clima")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setTicker(body)
            .setPriority(if (severe) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setCategory(if (severe) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .build()

        try {
            nmCompat.notify(notifId, notification)
            Logger.info("weather_alert_notification_sent", feature = "weather_alerts",
                action = "notify", correlationId = corrId,
                payload = mapOf("notif_id" to notifId.toString(), "severe" to severe.toString()))
        } catch (e: SecurityException) {
            Logger.error("weather_alert_notification_failed", feature = "weather_alerts",
                action = "notify", correlationId = corrId, exception = e)
        }
    }

    // Cria os canais necessários (só no O+). O canal normal reaproveita o
    // IMPORTANCE_MAX dos gatilhos; o severo é próprio, com som de alarme.
    private fun ensureChannels(context: Context, severe: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_MAX
            ).apply {
                enableVibration(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            })
        }

        if (severe && nm.getNotificationChannel(SEVERE_CHANNEL) == null) {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            nm.createNotificationChannel(NotificationChannel(
                SEVERE_CHANNEL, SEVERE_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alertas de tempo severo (tempestade, chuva forte)"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 600)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                if (alarmUri != null) setSound(alarmUri, attrs)
            })
        }
    }

    // Lê um double gravado pelo shared_preferences do Flutter, tolerando qualquer
    // encoding (Long rawBits, Float, Double, Int ou String com/sem prefixo).
    private fun readFlutterDouble(prefs: SharedPreferences, key: String): Double? {
        val raw = prefs.all[key] ?: return null
        return when (raw) {
            is Double -> raw
            is Float  -> raw.toDouble()
            is Long   -> java.lang.Double.longBitsToDouble(raw)
            is Int    -> raw.toDouble()
            is String -> {
                val s = if (raw.startsWith(DOUBLE_PREFIX)) raw.substring(DOUBLE_PREFIX.length) else raw
                s.toDoubleOrNull()
            }
            else -> null
        }
    }
}
