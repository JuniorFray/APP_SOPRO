package com.sopro.sopro

import android.content.Context
import com.sopro.sopro.logging.Logger
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// Autenticação Supabase (GoTrue) para o lado NATIVO (Overlay, sem Flutter Engine).
//
// Fase 1 — Contas: capacidade preparada, ainda NÃO consumida por nenhuma chamada
// de dados (dados seguem locais). O Overlay já fala HTTP direto (Gemini/Groq/clima);
// aqui ele ganha o mesmo para o Supabase Auth.
//
// Fonte dos tokens: FlutterSharedPreferences, gravados pelo AuthService.dart com as
// chaves "flutter.sopro_*". O refresh reescreve os novos tokens de volta no MESMO
// arquivo, de forma que o app (Dart) e o Overlay compartilham sempre o par atual.
//
// Todos os métodos de rede são BLOQUEANTES — chame sempre de uma thread de fundo
// (o Overlay já faz isso para as outras chamadas HTTP).
object SupabaseAuth {

    // Mesma dupla URL/chave usada pelo logging (publishable key — não é segredo).
    private const val AUTH_BASE = "https://zqgkfqenrljtncoecegv.supabase.co"
    private const val ANON_KEY  = "sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09"

    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_ACCESS  = "flutter.sopro_access_token"
    private const val KEY_REFRESH = "flutter.sopro_refresh_token"
    private const val KEY_EXPIRES = "flutter.sopro_token_expires_at" // epoch SEGUNDOS (String)
    private const val KEY_EMAIL   = "flutter.sopro_user_email"
    private const val KEY_USERID  = "flutter.sopro_user_id"

    // Margem: considera "expirado" 60s antes do fim real (mesma regra do Dart).
    private const val EXPIRY_MARGIN_SECONDS = 60L

    // Retorna um access_token VÁLIDO, fazendo refresh se estiver vencido.
    // null → não há sessão, ou o refresh falhou (sem internet / refresh_token morto).
    fun getValidAccessTokenBlocking(context: Context): String? {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val access = prefs.getString(KEY_ACCESS, null) ?: return null
        if (!isExpired(prefs)) return access
        // Vencido: tenta renovar. Sucesso reescreve KEY_ACCESS.
        return if (refreshBlocking(context)) {
            context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_ACCESS, null)
        } else null
    }

    // Força o refresh do par de tokens via GoTrue. Retorna true se renovou e salvou.
    // Usado pelo getValidAccessToken (quando vencido) e pelo hook de teste.
    fun refreshBlocking(context: Context): Boolean {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val refresh = prefs.getString(KEY_REFRESH, null) ?: return false

        var conn: HttpURLConnection? = null
        return try {
            val url = URL("$AUTH_BASE/auth/v1/token?grant_type=refresh_token")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod  = "POST"
                connectTimeout = 10_000
                readTimeout    = 10_000
                doOutput       = true
                setRequestProperty("apikey",        ANON_KEY)
                setRequestProperty("Authorization", "Bearer $ANON_KEY")
                setRequestProperty("Content-Type",  "application/json; charset=utf-8")
            }
            val body = JSONObject().put("refresh_token", refresh).toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            if (code !in 200..299) {
                // 400/401 → refresh_token inválido/revogado: limpa a sessão local.
                if (code == 400 || code == 401) clearSession(prefs)
                Logger.warn("overlay_auth_refresh_http", feature = "auth",
                    action = "refresh", payload = mapOf("http" to code.toString()))
                return false
            }
            val json = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
            val newAccess  = json.optString("access_token", "")
            val newRefresh = json.optString("refresh_token", "")
            if (newAccess.isEmpty() || newRefresh.isEmpty()) return false
            val expiresIn = json.optLong("expires_in", 3600L)
            val expiresAt = (System.currentTimeMillis() / 1000L) + expiresIn
            val user = json.optJSONObject("user")

            val editor = prefs.edit()
                .putString(KEY_ACCESS,  newAccess)
                .putString(KEY_REFRESH, newRefresh)
                .putString(KEY_EXPIRES, expiresAt.toString())
            if (user != null) {
                editor.putString(KEY_EMAIL,  user.optString("email", prefs.getString(KEY_EMAIL, "") ?: ""))
                editor.putString(KEY_USERID, user.optString("id",    prefs.getString(KEY_USERID, "") ?: ""))
            }
            editor.apply()

            Logger.info("overlay_auth_refreshed", feature = "auth", action = "refresh",
                payload = mapOf("expires_at" to expiresAt.toString()))
            true
        } catch (e: Exception) {
            Logger.warn("overlay_auth_refresh_error", feature = "auth",
                action = "refresh", exception = e)
            false
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    // Snapshot do estado de auth para o hook de teste/diagnóstico (sem rede).
    fun tokenInfo(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val access = prefs.getString(KEY_ACCESS, null)
        return mapOf(
            "hasToken"  to (access != null),
            "isExpired" to isExpired(prefs),
            "expiresAt" to (prefs.getString(KEY_EXPIRES, null) ?: ""),
            "email"     to (prefs.getString(KEY_EMAIL, "") ?: ""),
        )
    }

    // Força expiração (grava expires_at no passado) — só para o teste de refresh.
    fun simulateExpiryForTest(context: Context) {
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_EXPIRES, "0")
            .apply()
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun isExpired(prefs: android.content.SharedPreferences): Boolean {
        val expStr = prefs.getString(KEY_EXPIRES, null) ?: return true
        val expSecs = expStr.toLongOrNull() ?: return true
        val nowSecs = System.currentTimeMillis() / 1000L
        return nowSecs >= (expSecs - EXPIRY_MARGIN_SECONDS)
    }

    private fun clearSession(prefs: android.content.SharedPreferences) {
        prefs.edit()
            .remove(KEY_ACCESS)
            .remove(KEY_REFRESH)
            .remove(KEY_EXPIRES)
            .remove(KEY_EMAIL)
            .remove(KEY_USERID)
            .apply()
    }
}
