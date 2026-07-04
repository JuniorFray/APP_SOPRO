package com.sopro.sopro

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONObject
import java.io.File
import java.util.UUID

// TransparentVoiceActivity — activity totalmente transparente que processa ações
// de voz do FloatingVoiceService (criar trigger ou criar ambiente) sem tornar
// o app visível ao usuário.
//
// Escreve diretamente no SQLite — sem Flutter Engine, sem Dart VM, zero latência.
// Mesma abordagem do BootReceiver: leitura/escrita nativa via SQLiteDatabase.
//
// Fluxo:
//   FloatingVoiceService → SharedPreferences "sopro_voice" → startActivity(esta)
//   → lê intent JSON → escreve no SQLite → registra geofence (se ambiente) → finish()
//
// As streams do Drift são atualizadas na próxima vez que o usuário abre o app,
// quando o Drift faz nova query ao banco — comportamento aceitável para comandos
// de voz em background.
class TransparentVoiceActivity : Activity() {

    companion object {
        private const val TAG          = "TransparentVoice"
        // Mesma chave do AppLogger.dart / FloatingVoiceService.kt — INSERT-only por RLS
        private const val SUPABASE_URL = "https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/app_logs"
        private const val SUPABASE_KEY = "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Janela completamente transparente — zero visibilidade para o usuário
        window.setBackgroundDrawableResource(android.R.color.transparent)

        val prefs      = getSharedPreferences(VoiceActionReceiver.PREFS_NAME, MODE_PRIVATE)
        val actionJson = prefs.getString(VoiceActionReceiver.KEY_PENDING, null)
        val actionTime = prefs.getLong(VoiceActionReceiver.KEY_PENDING_TIME, 0L)

        // Ações mais antigas que 30 s são descartadas (evita reprocessamento de comandos velhos)
        if (actionJson == null || System.currentTimeMillis() - actionTime >= 30_000L) {
            Log.d(TAG, "Sem ação pendente ou ação expirada — encerrando")
            finish(); return
        }

        // Limpa imediatamente — idempotente se a activity for recriada pelo sistema
        prefs.edit()
            .remove(VoiceActionReceiver.KEY_PENDING)
            .remove(VoiceActionReceiver.KEY_PENDING_TIME)
            .apply()

        try {
            val json = JSONObject(actionJson)
            when (json.getString("intent")) {
                "create_environment" -> createEnvironment(json)   // assíncrono — finish() nos callbacks
                "create_trigger"     -> { createTrigger(json); finish() }
                else                 -> { Log.d(TAG, "Intent desconhecida — ignorada"); finish() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao processar ação de voz: ${e.message}")
            finish()
        }
    }

    // Obtém GPS e cria o ambiente no SQLite + registra geofence nativo.
    // Assíncrono — finish() é chamado dentro dos callbacks do FusedLocationProviderClient.
    private fun createEnvironment(json: JSONObject) {
        val name = json.optString("environment", "").trim()
        if (name.isEmpty()) {
            Log.w(TAG, "create_environment sem nome — abortando")
            finish(); return
        }
        val radius = json.optInt("radius", 100)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "ACCESS_FINE_LOCATION não concedido — ambiente não criado")
            finish(); return
        }

        LocationServices.getFusedLocationProviderClient(this).lastLocation
            .addOnSuccessListener { location ->
                if (location == null) {
                    Log.w(TAG, "GPS retornou null — ambiente não criado")
                    finish(); return@addOnSuccessListener
                }
                val id  = UUID.randomUUID().toString()
                val now = System.currentTimeMillis()
                writeEnvironmentToDb(id, name, location.latitude, location.longitude, radius, now)
                registerGeofence(id, name, location.latitude, location.longitude, radius.toDouble())
                finish()
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Erro ao obter localização: ${e.message}")
                finish()
            }
    }

    // Cria trigger no SQLite buscando environment_id pelo nome do ambiente.
    // Síncrono — finish() é chamado pelo chamador após retornar.
    private fun createTrigger(json: JSONObject) {
        val envName = json.optString("environment", "").trim()
        val title   = json.optString("title", "").trim()
        val content = json.optString("content", "")

        if (envName.isEmpty() || title.isEmpty()) {
            Log.w(TAG, "create_trigger sem envName ou title — abortando")
            return
        }

        val dbFile = findDbFile() ?: run {
            Log.w(TAG, "sopro.db não encontrado — trigger não criado")
            return
        }

        try {
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                .use { db ->
                    // Busca o ID do ambiente pelo nome (case-insensitive)
                    db.rawQuery(
                        "SELECT id FROM environments WHERE LOWER(name) = LOWER(?) LIMIT 1",
                        arrayOf(envName)
                    ).use { cursor ->
                        val envId = if (cursor.moveToFirst()) cursor.getString(0) else null
                        if (envId == null) {
                            Log.w(TAG, "Ambiente '$envName' não encontrado — trigger não criado")
                            return@use
                        }
                        val id  = UUID.randomUUID().toString()
                        val now = System.currentTimeMillis()
                        // Colunas baseadas na definição Drift de triggers_table.dart:
                        // id, environment_id, title, content, is_active (1=true), created_at (ms)
                        db.execSQL(
                            "INSERT INTO triggers (id, environment_id, title, content, is_active, created_at) VALUES (?, ?, ?, ?, 1, ?)",
                            arrayOf(id, envId, title, content, now)
                        )
                        Log.d(TAG, "Trigger '$title' criado em '$envName' ✓")
                    }
                }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao criar trigger no SQLite: ${e.message}")
        }
    }

    // Insere nova linha na tabela environments.
    // Colunas baseadas na definição Drift de environments_table.dart.
    private fun writeEnvironmentToDb(
        id: String, name: String, lat: Double, lon: Double, radius: Int, now: Long
    ) {
        val dbFile = findDbFile() ?: run {
            Log.w(TAG, "sopro.db não encontrado — ambiente não persistido")
            return
        }
        try {
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
                .use { db ->
                    try {
                        db.execSQL(
                            "INSERT INTO environments (id, name, latitude, longitude, radius_meters, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                            arrayOf(id, name, lat, lon, radius.toDouble(), now)
                        )
                        Log.d(TAG, "Ambiente '$name' criado ($lat, $lon, raio=${radius}m) ✓")
                        // Loga sucesso no Supabase — fire-and-forget em thread separada
                        val body = """{"device_id":"floating","event_type":"floating_env_created","payload":{"name":"$name","lat":$lat,"lon":$lon}}"""
                        logToSupabase(body)
                    } catch (e: Exception) {
                        Log.e(TAG, "Erro ao inserir ambiente no SQLite: ${e.message}")
                        // Loga falha no Supabase para diagnóstico remoto
                        val errMsg = e.message?.replace("\"", "'") ?: "unknown"
                        val body = """{"device_id":"floating","event_type":"floating_env_error","payload":{"error":"$errMsg","name":"$name"}}"""
                        logToSupabase(body)
                    }
                }
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao abrir banco para ambiente: ${e.message}")
        }
    }

    // Registra geofence nativo sem Flutter Engine — idêntico ao padrão do BootReceiver.kt.
    // Persiste o nome nas SharedPreferences para que o GeofenceReceiver exiba na notificação.
    @SuppressLint("MissingPermission") // permissão verificada em createEnvironment() antes de chamar
    private fun registerGeofence(
        id: String, name: String, lat: Double, lon: Double, radius: Double
    ) {
        getSharedPreferences(GeofenceReceiver.PREFS_NAME, MODE_PRIVATE)
            .edit().putString(id, name).apply()

        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(lat, lon, radius.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
            )
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0) // não dispara imediatamente ao registrar
            .addGeofence(geofence)
            .build()

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(
            this, id.hashCode(),
            Intent(this, GeofenceReceiver::class.java),
            flags
        )

        LocationServices.getGeofencingClient(this)
            .addGeofences(request, pendingIntent)
            .addOnSuccessListener { Log.d(TAG, "Geofence '$name' registrado ✓") }
            .addOnFailureListener { e ->
                Log.e(TAG, "Falha ao registrar geofence '$name': ${e.message}")
            }
    }

    // Fire-and-forget: envia body JSON já montado para o Supabase em thread separada.
    // Falhas de rede são silenciosas — logging nunca bloqueia o fluxo principal.
    private fun logToSupabase(body: String) {
        Thread {
            try {
                val conn = (java.net.URL(SUPABASE_URL).openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 5_000; readTimeout = 5_000; doOutput = true
                    setRequestProperty("Content-Type",  "application/json")
                    setRequestProperty("apikey",        SUPABASE_KEY)
                    setRequestProperty("Authorization", "Bearer $SUPABASE_KEY")
                    setRequestProperty("Prefer",        "return=minimal")
                }
                conn.outputStream.use { it.write(body.toByteArray()) }
                conn.responseCode // consome a resposta
                conn.disconnect()
            } catch (_: Exception) {}
        }.start()
    }

    // Retorna o caminho canônico do banco: /data/data/com.sopro.sopro/databases/sopro.db
    private fun findDbFile(): File? = getDatabasePath("sopro.db")

    // Sem animação de transição ao fechar — activity nunca deve ser visível ao usuário
    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }
}
