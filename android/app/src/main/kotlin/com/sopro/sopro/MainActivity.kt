package com.sopro.sopro

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import com.sopro.sopro.logging.CorrelationManager
import com.sopro.sopro.logging.Logger
import com.sopro.sopro.logging.LoggerConfiguration
import com.sopro.sopro.logging.SessionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

// MainActivity expõe GPS, BLE Social e Geofencing nativo ao Flutter via canais nativos.
//
// ── GPS (Sprint 5) ──────────────────────────────────────────────────────────
// MethodChannel "com.sopro.sopro/location":
//   checkPermission / requestPermission / getCurrentPosition
// EventChannel "com.sopro.sopro/location_stream":
//   Stream de posição a cada 2s / 10m
//
// ── BLE Social (Sprint 7) ───────────────────────────────────────────────────
// MethodChannel "com.sopro.sopro/ble":
//   checkPermissions / requestPermissions
//   startAdvertising({cardJson}) / stopAdvertising
//   getAdapterState → "on" | "off" | "unavailable"
//   connectAndReadCard({deviceId}) → String (cardJson) ou erro
//
// EventChannel "com.sopro.sopro/ble_scan":
//   onListen  → inicia scan filtrado pelo SERVICE_UUID Sopro
//   Eventos   → Map {deviceId, deviceName, rssi}
//   onCancel  → para scan
//
// ── Geofencing nativo (Sprint 13) ───────────────────────────────────────────
// MethodChannel "com.sopro.sopro/native_geofence":
//   addGeofence({id, lat, lng, radius, name}) — registra no GeofencingClient
//   removeGeofence({id})                      — remove pelo ID do ambiente
//   clearGeofences()                          — remove todos os geofences
//   hasBackgroundLocationPermission()         — bool (Android 10+)
//   requestBackgroundLocationPermission()     — bool (abre dialog/Configurações)
//
// O GeofencingClient do Android gerencia as zonas mesmo com o app fechado:
// ao entrar num geofence, o sistema aciona o GeofenceReceiver que envia
// a notificação via NotificationManager sem depender do app estar vivo.
//
// Peripheral role: BluetoothLeAdvertiser + BluetoothGattServer
// Central role:    BluetoothLeScanner + BluetoothGatt (GATT client)
class MainActivity : FlutterActivity() {

    companion object {
        // ── GPS ───────────────────────────────────────────────────────────────
        private const val LOCATION_CHANNEL  = "com.sopro.sopro/location"
        private const val STREAM_CHANNEL    = "com.sopro.sopro/location_stream"
        private const val PERM_REQUEST_LOC  = 1001

        // ── BLE ───────────────────────────────────────────────────────────────
        private const val BLE_CHANNEL       = "com.sopro.sopro/ble"
        private const val BLE_SCAN_CHANNEL  = "com.sopro.sopro/ble_scan"
        private const val PERM_REQUEST_BLE  = 1002

        // ── Geofencing nativo ─────────────────────────────────────────────────
        private const val GEOFENCE_CHANNEL      = "com.sopro.sopro/native_geofence"
        private const val PERM_REQUEST_BG_LOC   = 1003
        // SharedPreferences compartilhadas com GeofenceReceiver: {envId → envName}
        private const val PREFS_GEOFENCE_NAMES  = GeofenceReceiver.PREFS_NAME

        // ── Overlay (botão flutuante de voz) ──────────────────────────────────
        private const val OVERLAY_CHANNEL = "com.sopro.sopro/overlay"
        private const val TAG             = "MainActivity"

        // UUIDs Sopro — FIXOS (nunca alterar; identificam o app na rede BLE)
        private val SERVICE_UUID           = ParcelUuid.fromString("550e8400-e29b-41d4-a716-446655440000")
        private val CONTEXT_CARD_CHAR_UUID = UUID.fromString("550e8401-e29b-41d4-a716-446655440000")

        // Timeout para conexão GATT ao buscar ContextCard de outro dispositivo
        private const val GATT_TIMEOUT_MS  = 10_000L
    }

    // ── GPS ───────────────────────────────────────────────────────────────────
    private var fusedClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var locationEventSink: EventChannel.EventSink? = null
    private var pendingLocPermResult: MethodChannel.Result? = null

    // ── Geofencing nativo ─────────────────────────────────────────────────────
    private lateinit var geofencingClient: GeofencingClient
    // PendingIntent que aponta para GeofenceReceiver; reutilizado em todas as chamadas
    private var geofencePendingIntent: PendingIntent? = null
    private var pendingBgLocResult: MethodChannel.Result? = null

    // ── BLE peripheral (advertising + GATT server) ────────────────────────────
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var currentCardJson: String = "{}"
    private var pendingBlePermResult: MethodChannel.Result? = null

    // ── BLE central (scan + GATT client) ─────────────────────────────────────
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var scanEventSink: EventChannel.EventSink? = null
    private val activeGatts = mutableListOf<BluetoothGatt>()

    // Handler da main thread usado em callbacks GATT (que chegam em threads de fundo)
    private val mainHandler = Handler(Looper.getMainLooper())

    // Canal de overlay — armazenado para invocar métodos Dart a partir do onNewIntent
    private var overlayChannel: MethodChannel? = null

    // ═════════════════════════════════════════════════════════════════════════
    // Ciclo de vida da Activity
    // ═════════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        val startTime = System.currentTimeMillis()
        super.onCreate(savedInstanceState)
        SessionManager.init(this)
        if (savedInstanceState != null) {
            Logger.info("activity_recreated", feature = "main_activity", action = "onCreate",
                payload = mapOf("reason" to "system_recreation"),
                durationMs = System.currentTimeMillis() - startTime)
        } else {
            Logger.info("activity_created", feature = "main_activity", action = "onCreate",
                durationMs = System.currentTimeMillis() - startTime)
        }
    }

    override fun onStart() {
        super.onStart()
        Logger.debug("activity_started", feature = "main_activity", action = "onStart")
    }

    override fun onResume() {
        super.onResume()
        Logger.debug("activity_resumed", feature = "main_activity", action = "onResume")
    }

    override fun onPause() {
        Logger.debug("activity_paused", feature = "main_activity", action = "onPause")
        super.onPause()
    }

    override fun onStop() {
        Logger.debug("activity_stopped", feature = "main_activity", action = "onStop")
        super.onStop()
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Inicialização dos canais Flutter ↔ Native
    // ═════════════════════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val engineStart = System.currentTimeMillis()
        Logger.info("flutter_engine_configuring", feature = "main_activity",
            action = "configureFlutterEngine")
        super.configureFlutterEngine(flutterEngine)

        fusedClient       = LocationServices.getFusedLocationProviderClient(this)
        geofencingClient  = LocationServices.getGeofencingClient(this)

        // ── GPS: MethodChannel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                Logger.debug("method_channel_call", feature = "location", action = call.method,
                    payload = mapOf("channel" to LOCATION_CHANNEL))
                when (call.method) {
                    "checkPermission" -> {
                        val granted = hasLocationPermission()
                        Logger.debug("permission_check", feature = "location", action = call.method,
                            payload = mapOf("granted" to granted.toString()))
                        result.success(granted)
                    }
                    "requestPermission" -> {
                        Logger.info("permission_requested", feature = "location", action = call.method,
                            payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
                        requestLocationPermission(result)
                    }
                    "getCurrentPosition" -> {
                        Logger.debug("location_fetch_start", feature = "location", action = call.method)
                        getCurrentPosition(result)
                    }
                    else -> {
                        Logger.warn("method_channel_not_implemented", feature = "location",
                            action = call.method, payload = mapOf("channel" to LOCATION_CHANNEL))
                        result.notImplemented()
                    }
                }
            }
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to LOCATION_CHANNEL))

        // ── GPS: EventChannel (stream contínuo de posição) ────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    Logger.info("location_stream_started", feature = "location", action = "stream")
                    locationEventSink = events
                    startLocationStream()
                }
                override fun onCancel(args: Any?) {
                    Logger.info("location_stream_cancelled", feature = "location", action = "stream")
                    stopLocationStream()
                    locationEventSink = null
                }
            })
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to STREAM_CHANNEL))

        // ── BLE: MethodChannel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                Logger.debug("method_channel_call", feature = "ble", action = call.method,
                    payload = mapOf("channel" to BLE_CHANNEL))
                when (call.method) {
                    "checkPermissions" -> {
                        val granted = hasBluetoothPermissions()
                        Logger.debug("permission_check", feature = "ble", action = call.method,
                            payload = mapOf("granted" to granted.toString()))
                        result.success(granted)
                    }
                    "requestPermissions" -> {
                        Logger.info("permission_requested", feature = "ble", action = call.method,
                            payload = mapOf("permissions" to "BLE_SCAN,BLE_CONNECT,BLE_ADVERTISE"))
                        requestBluetoothPermissions(result)
                    }
                    "startAdvertising" -> {
                        val cardJson = call.argument<String>("cardJson") ?: "{}"
                        // txPower: 0=ULTRA_LOW, 1=LOW (padrão), 2=MEDIUM, 3=HIGH
                        val txPower = call.argument<Int>("txPower") ?: 1
                        Logger.info("ble_advertising_request", feature = "ble", action = call.method,
                            payload = mapOf("tx_power" to txPower.toString()))
                        startBleAdvertising(cardJson, txPower, result)
                    }
                    "stopAdvertising" -> {
                        Logger.info("ble_advertising_stop_request", feature = "ble", action = call.method)
                        stopBleAdvertising()
                        result.success(null)
                    }
                    "getAdapterState" -> {
                        val state = getAdapterState()
                        Logger.debug("ble_adapter_state", feature = "ble", action = call.method,
                            payload = mapOf("state" to state))
                        result.success(state)
                    }
                    "connectAndReadCard" -> {
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        if (deviceId.isEmpty()) {
                            Logger.warn("method_channel_invalid_args", feature = "ble",
                                action = call.method, payload = mapOf("missing_arg" to "deviceId"))
                            result.error("INVALID_ARGS", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        Logger.info("ble_gatt_connect_request", feature = "ble", action = call.method,
                            payload = mapOf("device_id" to deviceId))
                        connectAndReadCard(deviceId, result)
                    }
                    else -> {
                        Logger.warn("method_channel_not_implemented", feature = "ble",
                            action = call.method, payload = mapOf("channel" to BLE_CHANNEL))
                        result.notImplemented()
                    }
                }
            }
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to BLE_CHANNEL))

        // ── BLE: EventChannel (stream de resultados do scan) ──────────────────
        // Padrão espelhando o GPS stream: onListen inicia o scan, onCancel o para.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_SCAN_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    Logger.info("ble_scan_started", feature = "ble", action = "scan")
                    scanEventSink = events
                    startBleScan()
                }
                override fun onCancel(args: Any?) {
                    Logger.info("ble_scan_cancelled", feature = "ble", action = "scan")
                    stopBleScan()
                    scanEventSink = null
                }
            })
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to BLE_SCAN_CHANNEL))

        // ── Overlay (botão flutuante de voz): MethodChannel ──────────────────
        overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                Logger.debug("method_channel_call", feature = "overlay", action = call.method,
                    payload = mapOf("channel" to OVERLAY_CHANNEL))
                when (call.method) {
                    "hasOverlayPermission" -> {
                        val hasPermission = Settings.canDrawOverlays(this)
                        Logger.debug("overlay_permission_check", feature = "overlay",
                            action = call.method, payload = mapOf("granted" to hasPermission.toString()))
                        result.success(hasPermission)
                    }

                    "startFloatingVoiceService" -> {
                        val svcIntent = Intent(this, FloatingVoiceService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(svcIntent)
                        } else {
                            startService(svcIntent)
                        }
                        Logger.info("service_started", feature = "overlay", action = call.method,
                            payload = mapOf("service" to "FloatingVoiceService"))
                        result.success(null)
                    }

                    "stopFloatingVoiceService" -> {
                        stopService(Intent(this, FloatingVoiceService::class.java))
                        Logger.info("service_stopped", feature = "overlay", action = call.method,
                            payload = mapOf("service" to "FloatingVoiceService"))
                        result.success(null)
                    }

                    "openOverlayPermissionSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        startActivity(intent)
                        Logger.info("overlay_permission_settings_opened", feature = "overlay",
                            action = call.method)
                        result.success(null)
                    }

                    else -> {
                        Logger.warn("method_channel_not_implemented", feature = "overlay",
                            action = call.method, payload = mapOf("channel" to OVERLAY_CHANNEL))
                        result.notImplemented()
                    }
                }
            }
        }
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to OVERLAY_CHANNEL))

        // ── Geofencing nativo: MethodChannel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEOFENCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                Logger.debug("method_channel_call", feature = "geofence", action = call.method,
                    payload = mapOf("channel" to GEOFENCE_CHANNEL))
                when (call.method) {
                    "addGeofence" -> {
                        val id     = call.argument<String>("id") ?: run {
                            Logger.warn("method_channel_invalid_args", feature = "geofence",
                                action = call.method, payload = mapOf("missing_arg" to "id"))
                            return@setMethodCallHandler
                        }
                        val lat    = call.argument<Double>("lat") ?: run {
                            Logger.warn("method_channel_invalid_args", feature = "geofence",
                                action = call.method, payload = mapOf("missing_arg" to "lat"))
                            return@setMethodCallHandler
                        }
                        val lng    = call.argument<Double>("lng") ?: run {
                            Logger.warn("method_channel_invalid_args", feature = "geofence",
                                action = call.method, payload = mapOf("missing_arg" to "lng"))
                            return@setMethodCallHandler
                        }
                        val radius = call.argument<Double>("radius") ?: run {
                            Logger.warn("method_channel_invalid_args", feature = "geofence",
                                action = call.method, payload = mapOf("missing_arg" to "radius"))
                            return@setMethodCallHandler
                        }
                        val name   = call.argument<String>("name") ?: id
                        addNativeGeofence(id, lat, lng, radius.toFloat(), name, result)
                    }
                    "removeGeofence" -> {
                        val id = call.argument<String>("id") ?: run {
                            Logger.warn("method_channel_invalid_args", feature = "geofence",
                                action = call.method, payload = mapOf("missing_arg" to "id"))
                            return@setMethodCallHandler
                        }
                        Logger.info("geofence_remove_request", feature = "geofence",
                            action = call.method, payload = mapOf("id" to id))
                        geofencingClient.removeGeofences(listOf(id))
                            .addOnSuccessListener {
                                // Remove também o nome salvo nas prefs
                                getSharedPreferences(PREFS_GEOFENCE_NAMES, MODE_PRIVATE)
                                    .edit().remove(id).apply()
                                Logger.info("geofence_removed", feature = "geofence",
                                    action = call.method, payload = mapOf("id" to id))
                                result.success(null)
                            }
                            .addOnFailureListener { e ->
                                Logger.error("geofence_remove_failed", feature = "geofence",
                                    action = call.method, exception = e,
                                    payload = mapOf("id" to id))
                                result.error("REMOVE_FAILED", e.message, null)
                            }
                    }
                    "clearGeofences" -> {
                        val pi = geofencePendingIntent
                        if (pi != null) {
                            Logger.info("geofences_clear_request", feature = "geofence",
                                action = call.method)
                            geofencingClient.removeGeofences(pi)
                                .addOnSuccessListener {
                                    getSharedPreferences(PREFS_GEOFENCE_NAMES, MODE_PRIVATE)
                                        .edit().clear().apply()
                                    Logger.info("geofences_cleared", feature = "geofence",
                                        action = call.method)
                                    result.success(null)
                                }
                                .addOnFailureListener { e ->
                                    Logger.error("geofences_clear_failed", feature = "geofence",
                                        action = call.method, exception = e)
                                    result.error("CLEAR_FAILED", e.message, null)
                                }
                        } else {
                            Logger.debug("geofences_clear_noop", feature = "geofence",
                                action = call.method,
                                payload = mapOf("reason" to "no_pending_intent"))
                            result.success(null) // nenhum geofence registrado ainda
                        }
                    }
                    "hasBackgroundLocationPermission" -> {
                        val granted = hasBackgroundLocationPermission()
                        Logger.debug("permission_check", feature = "geofence", action = call.method,
                            payload = mapOf("permission" to "ACCESS_BACKGROUND_LOCATION",
                                "granted" to granted.toString()))
                        result.success(granted)
                    }
                    "requestBackgroundLocationPermission" -> {
                        Logger.info("permission_requested", feature = "geofence", action = call.method,
                            payload = mapOf("permission" to "ACCESS_BACKGROUND_LOCATION"))
                        requestBackgroundLocationPermission(result)
                    }
                    else -> {
                        Logger.warn("method_channel_not_implemented", feature = "geofence",
                            action = call.method, payload = mapOf("channel" to GEOFENCE_CHANNEL))
                        result.notImplemented()
                    }
                }
            }
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to GEOFENCE_CHANNEL))

        // ── Geocoder Benchmark Channel ────────────────────────────────────────
        // Canal temporário para testar o Geocoder nativo do Android.
        // Remove a entrada do menu após os testes — o código pode permanecer inerte.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sopro.sopro/geocoder")
            .setMethodCallHandler { call, result ->
                Logger.debug("method_channel_call", feature = "geocoder", action = call.method)
                when (call.method) {

                    // Busca até 5 endereços com bounding box opcional centrada no usuário (~55 km)
                    "searchAddress" -> {
                        val query   = call.argument<String>("query")  ?: ""
                        val userLat = call.argument<Double>("userLat") ?: 0.0
                        val userLon = call.argument<Double>("userLon") ?: 0.0
                        val startTime = System.currentTimeMillis()
                        Logger.debug("geocoder_search_start", feature = "geocoder", action = call.method,
                            payload = if (LoggerConfiguration.debugLogging)
                                mapOf("query" to query) else null)
                        try {
                            @Suppress("DEPRECATION")
                            val geocoder = android.location.Geocoder(
                                this, java.util.Locale("pt", "BR"))

                            // delta ~0.5° ≈ 55 km; limita resultados à região do usuário
                            val delta = 0.5
                            val addresses = if (userLat != 0.0 && userLon != 0.0) {
                                geocoder.getFromLocationName(
                                    query, 5,
                                    userLat - delta, userLon - delta,
                                    userLat + delta, userLon + delta
                                )
                            } else {
                                geocoder.getFromLocationName(query, 5)
                            }

                            val duration = (System.currentTimeMillis() - startTime).toInt()

                            if (!addresses.isNullOrEmpty()) {
                                val resultList = addresses.map { addr ->
                                    mapOf(
                                        "lat"              to addr.latitude,
                                        "lon"              to addr.longitude,
                                        "returned_address" to (addr.getAddressLine(0) ?: ""),
                                        "has_number"       to (!addr.subThoroughfare.isNullOrEmpty()),
                                        "name"             to (addr.featureName ?: ""),
                                        "city"             to (addr.locality ?: addr.subAdminArea ?: ""),
                                        "state"            to (addr.adminArea ?: "")
                                    )
                                }
                                Logger.debug("geocoder_search_result", feature = "geocoder",
                                    action = call.method,
                                    durationMs = duration.toLong(),
                                    payload = mapOf("found" to "true",
                                        "count" to addresses.size.toString()))
                                result.success(mapOf(
                                    "found"       to true,
                                    "results"     to resultList,
                                    "duration_ms" to duration
                                ))
                            } else {
                                Logger.debug("geocoder_search_result", feature = "geocoder",
                                    action = call.method,
                                    durationMs = duration.toLong(),
                                    payload = mapOf("found" to "false"))
                                result.success(mapOf(
                                    "found"       to false,
                                    "results"     to emptyList<Map<String, Any>>(),
                                    "duration_ms" to duration
                                ))
                            }
                        } catch (e: Exception) {
                            Logger.warn("geocoder_search_failed", feature = "geocoder",
                                action = call.method, exception = e,
                                durationMs = System.currentTimeMillis() - startTime)
                            result.success(mapOf(
                                "found"       to false,
                                "results"     to emptyList<Map<String, Any>>(),
                                "duration_ms" to 0
                            ))
                        }
                    }
                    // Geocoding reverso: lat/lon → nome do local mais próximo
                    "reverseGeocode" -> {
                        val lat = call.argument<Double>("lat") ?: 0.0
                        val lon = call.argument<Double>("lon") ?: 0.0
                        val startTime = System.currentTimeMillis()
                        Logger.debug("geocoder_reverse_start", feature = "geocoder", action = call.method)
                        try {
                            @Suppress("DEPRECATION")
                            val geocoder = android.location.Geocoder(
                                this, java.util.Locale("pt", "BR"))
                            val addresses = geocoder.getFromLocation(lat, lon, 1)
                            if (!addresses.isNullOrEmpty()) {
                                val addr = addresses[0]
                                // Prefere featureName, cai para thoroughfare, bairro ou cidade
                                val displayName = addr.featureName
                                    ?: addr.thoroughfare
                                    ?: addr.subLocality
                                    ?: addr.locality
                                    ?: "Local desconhecido"
                                Logger.debug("geocoder_reverse_result", feature = "geocoder",
                                    action = call.method,
                                    durationMs = System.currentTimeMillis() - startTime,
                                    payload = mapOf("found" to "true"))
                                result.success(mapOf(
                                    "found"            to true,
                                    "display_name"     to displayName,
                                    "returned_address" to (addr.getAddressLine(0) ?: ""),
                                    "lat"              to lat,
                                    "lon"              to lon
                                ))
                            } else {
                                Logger.debug("geocoder_reverse_result", feature = "geocoder",
                                    action = call.method,
                                    durationMs = System.currentTimeMillis() - startTime,
                                    payload = mapOf("found" to "false"))
                                result.success(mapOf("found" to false))
                            }
                        } catch (e: Exception) {
                            Logger.warn("geocoder_reverse_failed", feature = "geocoder",
                                action = call.method, exception = e,
                                durationMs = System.currentTimeMillis() - startTime)
                            result.success(mapOf("found" to false))
                        }
                    }

                    else -> {
                        Logger.warn("method_channel_not_implemented", feature = "geocoder",
                            action = call.method)
                        result.notImplemented()
                    }
                }
            }
        Logger.debug("channel_registered", feature = "main_activity", action = "configureFlutterEngine",
            payload = mapOf("channel" to "com.sopro.sopro/geocoder"))

        Logger.info("flutter_engine_configured", feature = "main_activity",
            action = "configureFlutterEngine",
            durationMs = System.currentTimeMillis() - engineStart,
            payload = mapOf("channels_count" to "6"))
    }

    // ═════════════════════════════════════════════════════════════════════════
    // GPS — permissão + posição pontual + stream
    // ═════════════════════════════════════════════════════════════════════════

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) {
            Logger.debug("permission_already_granted", feature = "location",
                action = "requestLocationPermission",
                payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
            result.success(true); return
        }
        pendingLocPermResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), PERM_REQUEST_LOC
        )
    }

    private fun getCurrentPosition(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            Logger.warn("location_permission_denied", feature = "location",
                action = "getCurrentPosition")
            result.error("PERMISSION_DENIED", "Location permission not granted", null); return
        }
        fusedClient?.lastLocation
            ?.addOnSuccessListener { loc ->
                if (loc != null) {
                    Logger.debug("location_obtained", feature = "location",
                        action = "getCurrentPosition",
                        payload = mapOf("source" to "last_known"))
                    result.success(locationMap(loc))
                } else {
                    Logger.debug("location_null_requesting_fresh", feature = "location",
                        action = "getCurrentPosition")
                    requestFreshLocation(result)
                }
            }
            ?.addOnFailureListener { e ->
                Logger.error("location_fetch_failed", feature = "location",
                    action = "getCurrentPosition", exception = e)
                result.error("LOCATION_ERROR", e.message, null)
            }
    }

    private fun requestFreshLocation(result: MethodChannel.Result) {
        Logger.debug("location_fresh_request", feature = "location", action = "requestFreshLocation")
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 0L)
            .setMaxUpdates(1).build()
        var done = false
        fusedClient?.requestLocationUpdates(req, object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                if (done) return
                done = true
                fusedClient?.removeLocationUpdates(this)
                val loc = lr.lastLocation
                if (loc != null) {
                    Logger.debug("location_obtained", feature = "location",
                        action = "requestFreshLocation", payload = mapOf("source" to "fresh"))
                    result.success(locationMap(loc))
                } else {
                    Logger.warn("location_null_fresh", feature = "location",
                        action = "requestFreshLocation")
                    result.error("NULL_LOCATION", "Could not obtain location", null)
                }
            }
        }, Looper.getMainLooper())
    }

    private fun startLocationStream() {
        if (!hasLocationPermission()) {
            Logger.warn("location_stream_permission_denied", feature = "location",
                action = "startLocationStream")
            return
        }
        Logger.debug("location_stream_starting", feature = "location", action = "startLocationStream")
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2_000L)
            .setMinUpdateDistanceMeters(10f).build()
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                lr.lastLocation?.let { loc ->
                    Logger.trace("location_update", feature = "location", action = "stream")
                    locationEventSink?.success(locationMap(loc))
                }
            }
        }
        fusedClient?.requestLocationUpdates(req, locationCallback!!, Looper.getMainLooper())
    }

    private fun stopLocationStream() {
        Logger.debug("location_stream_stopping", feature = "location", action = "stopLocationStream")
        locationCallback?.let { fusedClient?.removeLocationUpdates(it) }
        locationCallback = null
    }

    private fun locationMap(loc: android.location.Location) = mapOf(
        "latitude"  to loc.latitude,
        "longitude" to loc.longitude,
        "accuracy"  to loc.accuracy.toDouble()
    )

    // ═════════════════════════════════════════════════════════════════════════
    // Geofencing nativo — GeofencingClient + PendingIntent → GeofenceReceiver
    // ═════════════════════════════════════════════════════════════════════════

    // Cria (ou reutiliza) o PendingIntent que aponta para o GeofenceReceiver.
    // FLAG_MUTABLE é obrigatório no Android 12+ para o GeofencingClient injetar
    // os dados da transição no Intent antes de entregá-lo ao receiver.
    private fun getGeofencePendingIntent(): PendingIntent {
        geofencePendingIntent?.let { return it }
        val intent = Intent(this, GeofenceReceiver::class.java)
        val flags  = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        return PendingIntent.getBroadcast(this, 0, intent, flags)
            .also { geofencePendingIntent = it }
    }

    // Registra um geofence circular no GeofencingClient do Android.
    // O sistema Android monitorará o geofence mesmo após o app ser fechado.
    // [name] é salvo nas SharedPreferences para que o GeofenceReceiver possa
    // exibi-lo na notificação sem precisar acessar o banco de dados do app.
    @SuppressLint("MissingPermission") // permissão verificada em hasLocationPermission()
    private fun addNativeGeofence(
        id: String, lat: Double, lng: Double, radius: Float, name: String,
        result: MethodChannel.Result
    ) {
        val corrId = CorrelationManager.beginOperation("geofence_add")
        if (!hasLocationPermission()) {
            Logger.warn("geofence_permission_denied", feature = "geofence",
                action = "addNativeGeofence",
                payload = mapOf("permission" to "ACCESS_FINE_LOCATION"),
                correlationId = corrId)
            CorrelationManager.endOperation("geofence_add")
            result.error("PERMISSION_DENIED", "ACCESS_FINE_LOCATION required", null)
            return
        }

        Logger.info("geofence_add_request", feature = "geofence", action = "addNativeGeofence",
            payload = if (LoggerConfiguration.debugLogging)
                mapOf("name" to name, "id" to id,
                    "radius" to radius.toString())
            else mapOf("id" to id),
            correlationId = corrId)

        val geofence = Geofence.Builder()
            .setRequestId(id)                       // ID único = ID do ambiente no banco
            .setCircularRegion(lat, lng, radius)    // centro e raio em metros
            .setExpirationDuration(Geofence.NEVER_EXPIRE)   // permanente até removeGeofence()
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or
                Geofence.GEOFENCE_TRANSITION_EXIT
            )
            .build()

        val request = GeofencingRequest.Builder()
            // Não dispara ao registrar caso o usuário já esteja dentro do geofence;
            // o disparo acontece na próxima entrada detectada pelo sistema.
            .setInitialTrigger(0)
            .addGeofence(geofence)
            .build()

        geofencingClient.addGeofences(request, getGeofencePendingIntent())
            .addOnSuccessListener {
                // Persiste o nome do ambiente para uso offline pelo GeofenceReceiver
                getSharedPreferences(PREFS_GEOFENCE_NAMES, MODE_PRIVATE)
                    .edit().putString(id, name).apply()
                Logger.info("geofence_registered", feature = "geofence",
                    action = "addNativeGeofence",
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("name" to name, "id" to id) else mapOf("id" to id),
                    correlationId = corrId)
                CorrelationManager.endOperation("geofence_add")
                result.success(null)
            }
            .addOnFailureListener { e ->
                Logger.error("geofence_registration_failed", feature = "geofence",
                    action = "addNativeGeofence",
                    exception = e,
                    payload = if (LoggerConfiguration.debugLogging)
                        mapOf("name" to name, "id" to id) else mapOf("id" to id),
                    correlationId = corrId)
                CorrelationManager.endOperation("geofence_add")
                result.error("ADD_FAILED", e.message ?: "Unknown error", null)
            }
    }

    // Verifica se ACCESS_BACKGROUND_LOCATION foi concedido.
    // Necessário no Android 10+ para que o GeofenceReceiver seja acionado
    // quando o app não está em primeiro plano.
    private fun hasBackgroundLocationPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 9 e anteriores: ACCESS_FINE_LOCATION já cobre background
            hasLocationPermission()
        }

    // Solicita ACCESS_BACKGROUND_LOCATION ao usuário.
    // No Android 11+ o sistema exige que o usuário conceda manualmente via
    // Configurações > Apps > Sopro > Permissões > Localização > "Sempre".
    private fun requestBackgroundLocationPermission(result: MethodChannel.Result) {
        if (hasBackgroundLocationPermission()) {
            Logger.debug("permission_already_granted", feature = "geofence",
                action = "requestBackgroundLocationPermission",
                payload = mapOf("permission" to "ACCESS_BACKGROUND_LOCATION"))
            result.success(true); return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            pendingBgLocResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                PERM_REQUEST_BG_LOC
            )
        } else {
            result.success(true) // versões anteriores ao Android 10 não precisam
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE — permissões + estado do adaptador
    // ═════════════════════════════════════════════════════════════════════════

    private fun hasBluetoothPermissions(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)      == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)   == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
        } else {
            hasLocationPermission()
        }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (hasBluetoothPermissions()) {
            Logger.debug("permission_already_granted", feature = "ble",
                action = "requestBluetoothPermissions",
                payload = mapOf("permissions" to "BLE_SCAN,BLE_CONNECT,BLE_ADVERTISE"))
            result.success(true); return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            pendingBlePermResult = result
            ActivityCompat.requestPermissions(this, arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ), PERM_REQUEST_BLE)
        } else {
            requestLocationPermission(result)
        }
    }

    // Retorna estado legível do adaptador Bluetooth para o Dart
    private fun getAdapterState(): String {
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = btManager?.adapter ?: return "unavailable"
        return if (adapter.isEnabled) "on" else "off"
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE Peripheral — advertising + GATT server (expõe ContextCard)
    // ═════════════════════════════════════════════════════════════════════════

    // [txPower]: 0=ULTRA_LOW (~2m), 1=LOW (~5m), 2=MEDIUM (~10m), 3=HIGH (~20m+)
    // Mapeado diretamente para AdvertiseSettings.ADVERTISE_TX_POWER_* (mesmos valores).
    private fun startBleAdvertising(cardJson: String, txPower: Int, result: MethodChannel.Result) {
        val corrId = CorrelationManager.beginOperation("ble_advertising")
        if (!hasBluetoothPermissions()) {
            Logger.warn("ble_advertising_permission_denied", feature = "ble",
                action = "startBleAdvertising", correlationId = corrId)
            CorrelationManager.endOperation("ble_advertising")
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null); return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            Logger.warn("ble_adapter_disabled", feature = "ble", action = "startBleAdvertising",
                correlationId = corrId)
            CorrelationManager.endOperation("ble_advertising")
            result.error("BT_DISABLED", "Bluetooth is not enabled", null); return
        }

        currentCardJson = cardJson
        setupGattServer(btManager)

        advertiser = btAdapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            Logger.warn("ble_advertiser_unavailable", feature = "ble", action = "startBleAdvertising",
                correlationId = corrId)
            CorrelationManager.endOperation("ble_advertising")
            result.error("NO_ADVERTISER", "Device does not support BLE advertising", null); return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true)
            .setTimeout(0)
            // Nível de potência configurado pelo usuário nas Configurações do app
            .setTxPowerLevel(txPower.coerceIn(0, 3))
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(SERVICE_UUID)
            .setIncludeDeviceName(false)
            .build()

        var responded = false
        advertiser?.startAdvertising(settings, data, object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                Logger.info("ble_advertising_started", feature = "ble",
                    action = "startBleAdvertising",
                    payload = mapOf("tx_power" to txPower.toString()),
                    correlationId = corrId)
                CorrelationManager.endOperation("ble_advertising")
                if (!responded) { responded = true; result.success(true) }
            }
            override fun onStartFailure(errorCode: Int) {
                Logger.error("ble_advertising_failed", feature = "ble",
                    action = "startBleAdvertising",
                    payload = mapOf("error_code" to errorCode.toString()),
                    correlationId = corrId)
                CorrelationManager.endOperation("ble_advertising")
                if (!responded) { responded = true
                    result.error("ADVERTISE_FAILED", "Error code: $errorCode", null)
                }
            }
        })
    }

    private fun stopBleAdvertising() {
        try { advertiser?.stopAdvertising(object : AdvertiseCallback() {}) } catch (e: Exception) {
            Logger.warn("ble_stop_advertise_failed", feature = "ble",
                action = "stopBleAdvertising", exception = e)
        }
        advertiser = null
        try { gattServer?.close() } catch (e: Exception) {
            Logger.warn("gatt_server_close_failed", feature = "ble",
                action = "stopBleAdvertising", exception = e)
        }
        gattServer = null
    }

    // GATT server: responde leituras da characteristic de ContextCard.
    // Suporta Long Read (offset incremental) para payloads maiores que o MTU negociado.
    private fun setupGattServer(btManager: BluetoothManager) {
        try { gattServer?.close() } catch (e: Exception) {
            Logger.warn("gatt_server_close_failed", feature = "ble",
                action = "setupGattServer", exception = e)
        }

        gattServer = btManager.openGattServer(this, object : BluetoothGattServerCallback() {
            override fun onCharacteristicReadRequest(
                device: BluetoothDevice, requestId: Int, offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                if (characteristic.uuid != CONTEXT_CARD_CHAR_UUID) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                    return
                }
                val bytes = currentCardJson.toByteArray(Charsets.UTF_8)
                if (offset > bytes.size) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, 0, null)
                    return
                }
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS,
                    offset, bytes.copyOfRange(offset, bytes.size))
            }
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {}
        })

        val service = BluetoothGattService(
            UUID.fromString("550e8400-e29b-41d4-a716-446655440000"),
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        val char = BluetoothGattCharacteristic(
            CONTEXT_CARD_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(char)
        gattServer?.addService(service)
        Logger.debug("gatt_server_initialized", feature = "ble", action = "setupGattServer")
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE Central — scan (EventChannel) + GATT client (connectAndReadCard)
    // ═════════════════════════════════════════════════════════════════════════

    // Inicia scan BLE filtrando apenas dispositivos com o SERVICE_UUID Sopro.
    // Resultados são emitidos via scanEventSink (EventChannel) para o Dart.
    private fun startBleScan() {
        if (!hasBluetoothPermissions()) {
            Logger.warn("ble_scan_permission_denied", feature = "ble", action = "startBleScan")
            scanEventSink?.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            Logger.warn("ble_adapter_disabled", feature = "ble", action = "startBleScan")
            scanEventSink?.error("BT_DISABLED", "Bluetooth is not enabled", null)
            return
        }

        scanner = btAdapter.bluetoothLeScanner
        if (scanner == null) {
            Logger.warn("ble_scanner_unavailable", feature = "ble", action = "startBleScan")
            scanEventSink?.error("NO_SCANNER", "BLE scanner unavailable", null)
            return
        }

        val filter = ScanFilter.Builder()
            .setServiceUuid(SERVICE_UUID)
            .build()

        // SCAN_MODE_BALANCED: reduz frequência de callbacks vs LOW_LATENCY,
        // diminuindo detecções duplicadas do mesmo dispositivo em burst.
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                // Nome preferido: scanRecord contém o nome do advertisement
                val name = result.scanRecord?.deviceName
                    ?: result.device.name
                    ?: ""
                val info = mapOf(
                    "deviceId"   to result.device.address,
                    "deviceName" to name,
                    "rssi"       to result.rssi
                )
                Logger.trace("ble_scan_result", feature = "ble", action = "scan",
                    payload = mapOf("device_id" to result.device.address,
                        "rssi" to result.rssi.toString()))
                // ScanCallback pode ser chamado de thread de fundo — garante main thread
                mainHandler.post { scanEventSink?.success(info) }
            }
            override fun onScanFailed(errorCode: Int) {
                Logger.error("ble_scan_failed", feature = "ble", action = "scan",
                    payload = mapOf("error_code" to errorCode.toString()))
                mainHandler.post {
                    scanEventSink?.error("SCAN_FAILED", "Error code: $errorCode", null)
                }
            }
        }

        scanner?.startScan(listOf(filter), settings, scanCallback!!)
        Logger.debug("ble_scan_active", feature = "ble", action = "startBleScan",
            payload = mapOf("filter" to SERVICE_UUID.toString()))
    }

    private fun stopBleScan() {
        try { scanCallback?.let { scanner?.stopScan(it) } } catch (e: Exception) {
            Logger.warn("ble_stop_scan_failed", feature = "ble", action = "stopBleScan", exception = e)
        }
        Logger.debug("ble_scan_stopped", feature = "ble", action = "stopBleScan")
        scanCallback = null
        scanner = null
    }

    // Conecta ao dispositivo como cliente GATT, lê o ContextCard e desconecta.
    // Retorna o JSON do ContextCard via MethodChannel result.
    // Timeout de GATT_TIMEOUT_MS para evitar que a Promise fique pendente para sempre.
    private fun connectAndReadCard(deviceId: String, result: MethodChannel.Result) {
        val corrId = CorrelationManager.beginOperation("ble_gatt")
        if (!hasBluetoothPermissions()) {
            Logger.warn("ble_gatt_permission_denied", feature = "ble", action = "connectAndReadCard",
                correlationId = corrId)
            CorrelationManager.endOperation("ble_gatt")
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null); return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            Logger.warn("ble_adapter_disabled", feature = "ble", action = "connectAndReadCard",
                correlationId = corrId)
            CorrelationManager.endOperation("ble_gatt")
            result.error("BT_DISABLED", "Bluetooth is not enabled", null); return
        }

        val device = try {
            btAdapter.getRemoteDevice(deviceId)
        } catch (e: IllegalArgumentException) {
            Logger.warn("ble_gatt_invalid_device_id", feature = "ble", action = "connectAndReadCard",
                exception = e, payload = mapOf("device_id" to deviceId), correlationId = corrId)
            CorrelationManager.endOperation("ble_gatt")
            result.error("INVALID_ID", "Invalid device ID: $deviceId", null); return
        }

        // Fecha GATTs zumbis para este dispositivo antes de tentar nova conexão
        closeZombieGatts(deviceId)

        var responded = false
        var activeGatt: BluetoothGatt? = null

        // Garante que result seja chamado exatamente uma vez
        fun respond(block: () -> Unit) {
            if (!responded) {
                responded = true
                mainHandler.post(block)
            }
        }

        fun cleanup(gatt: BluetoothGatt) {
            try { gatt.disconnect() } catch (e: Exception) {
                Logger.warn("gatt_disconnect_failed", feature = "ble", exception = e,
                    correlationId = corrId)
            }
            mainHandler.postDelayed({
                try { gatt.close() } catch (e: Exception) {
                    Logger.warn("gatt_close_failed", feature = "ble", exception = e,
                        correlationId = corrId)
                }
                activeGatts.remove(gatt)
            }, 500L) // pequeno delay para que o disconnect seja processado
        }

        // Timeout: se nenhuma resposta chegar em GATT_TIMEOUT_MS, falha graciosamente
        val timeoutRunnable = Runnable {
            Logger.warn("ble_gatt_timeout", feature = "ble", action = "connectAndReadCard",
                durationMs = GATT_TIMEOUT_MS, payload = mapOf("device_id" to deviceId),
                correlationId = corrId)
            CorrelationManager.endOperation("ble_gatt")
            respond { result.error("TIMEOUT", "GATT connection timed out", null) }
            activeGatt?.let { cleanup(it) }
        }
        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Logger.debug("ble_gatt_connected", feature = "ble",
                            action = "connectAndReadCard",
                            payload = mapOf("device_id" to deviceId),
                            correlationId = corrId)
                        // Solicita MTU maior para suportar ContextCards de até 512 bytes
                        gatt.requestMtu(512)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        Logger.warn("ble_gatt_disconnected", feature = "ble",
                            action = "connectAndReadCard",
                            payload = mapOf("device_id" to deviceId, "status" to status.toString()),
                            correlationId = corrId)
                        CorrelationManager.endOperation("ble_gatt")
                        respond { result.error("DISCONNECTED", "Device disconnected (status=$status)", null) }
                        try { gatt.close() } catch (e: Exception) {
                            Logger.warn("gatt_close_failed", feature = "ble", exception = e,
                                correlationId = corrId)
                        }
                        activeGatts.remove(gatt)
                    }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                Logger.trace("ble_gatt_mtu_changed", feature = "ble", action = "connectAndReadCard",
                    payload = mapOf("mtu" to mtu.toString(), "status" to status.toString()),
                    correlationId = corrId)
                // Inicia descoberta de serviços após negociar MTU
                gatt.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    Logger.warn("ble_gatt_discovery_failed", feature = "ble",
                        action = "connectAndReadCard",
                        payload = mapOf("status" to status.toString()),
                        correlationId = corrId)
                    CorrelationManager.endOperation("ble_gatt")
                    respond { result.error("DISCOVERY_FAILED", "Service discovery failed: $status", null) }
                    cleanup(gatt); return
                }
                val service = gatt.getService(UUID.fromString("550e8400-e29b-41d4-a716-446655440000"))
                if (service == null) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    Logger.warn("ble_gatt_service_not_found", feature = "ble",
                        action = "connectAndReadCard", correlationId = corrId)
                    CorrelationManager.endOperation("ble_gatt")
                    respond { result.error("NO_SERVICE", "Sopro service not found", null) }
                    cleanup(gatt); return
                }
                val char = service.getCharacteristic(CONTEXT_CARD_CHAR_UUID)
                if (char == null) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    Logger.warn("ble_gatt_characteristic_not_found", feature = "ble",
                        action = "connectAndReadCard", correlationId = corrId)
                    CorrelationManager.endOperation("ble_gatt")
                    respond { result.error("NO_CHAR", "ContextCard characteristic not found", null) }
                    cleanup(gatt); return
                }
                Logger.debug("ble_gatt_services_discovered", feature = "ble",
                    action = "connectAndReadCard", correlationId = corrId)
                gatt.readCharacteristic(char)
            }

            // Callback legado (Android < 13) — suprimido pois ainda é chamado em < API 33
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    onReadResult(gatt, characteristic.value, status, result, timeoutRunnable)
                }
            }

            // Callback moderno (Android 13+)
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                onReadResult(gatt, value, status, result, timeoutRunnable)
            }

            private fun onReadResult(
                gatt: BluetoothGatt,
                value: ByteArray,
                status: Int,
                res: MethodChannel.Result,
                timeout: Runnable
            ) {
                mainHandler.removeCallbacks(timeout)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val cardJson = String(value, Charsets.UTF_8)
                    Logger.info("ble_gatt_read_success", feature = "ble",
                        action = "connectAndReadCard",
                        payload = mapOf("bytes" to value.size.toString()),
                        correlationId = corrId)
                    CorrelationManager.endOperation("ble_gatt")
                    respond { res.success(cardJson) }
                } else {
                    Logger.warn("ble_gatt_read_failed", feature = "ble",
                        action = "connectAndReadCard",
                        payload = mapOf("status" to status.toString()),
                        correlationId = corrId)
                    CorrelationManager.endOperation("ble_gatt")
                    respond { res.error("READ_FAILED", "Characteristic read failed: $status", null) }
                }
                cleanup(gatt)
            }
        }

        // Aguarda 600ms antes de conectar: Android precisa de tempo entre a descoberta
        // via scan e a tentativa de conexão GATT para evitar status=133 (conexão zumbi)
        mainHandler.postDelayed({
            Logger.debug("ble_gatt_connecting", feature = "ble", action = "connectAndReadCard",
                payload = mapOf("device_id" to deviceId), correlationId = corrId)
            activeGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            activeGatt?.let { activeGatts.add(it) }
            mainHandler.postDelayed(timeoutRunnable, GATT_TIMEOUT_MS)
        }, 600L)
    }

    // Fecha todos os GATTs ativos para um dispositivo antes de nova conexão.
    // Evita status=133 causado por conexões zumbi no Android BLE stack.
    private fun closeZombieGatts(deviceId: String) {
        val zombies = activeGatts.filter { it.device.address == deviceId }
        if (zombies.isNotEmpty()) {
            Logger.debug("ble_gatt_zombie_close", feature = "ble", action = "closeZombieGatts",
                payload = mapOf("device_id" to deviceId, "count" to zombies.size.toString()))
        }
        zombies.forEach { gatt ->
            try { gatt.disconnect() } catch (e: Exception) {
                Logger.warn("gatt_disconnect_failed", feature = "ble",
                    action = "closeZombieGatts", exception = e)
            }
            try { gatt.close() } catch (e: Exception) {
                Logger.warn("gatt_close_failed", feature = "ble",
                    action = "closeZombieGatts", exception = e)
            }
        }
        activeGatts.removeAll(zombies.toSet())
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Permissões — callback unificado GPS (1001) e BLE (1002)
    // ═════════════════════════════════════════════════════════════════════════

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            PERM_REQUEST_LOC -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    Logger.info("permission_granted", feature = "location",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
                } else {
                    Logger.warn("permission_denied", feature = "location",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permission" to "ACCESS_FINE_LOCATION"))
                }
                pendingLocPermResult?.success(granted)
                pendingLocPermResult = null
                if (granted && locationEventSink != null) startLocationStream()
            }
            PERM_REQUEST_BLE -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (granted) {
                    Logger.info("permission_granted", feature = "ble",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permissions" to "BLE_SCAN,BLE_CONNECT,BLE_ADVERTISE"))
                } else {
                    Logger.warn("permission_denied", feature = "ble",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permissions" to "BLE_SCAN,BLE_CONNECT,BLE_ADVERTISE"))
                }
                pendingBlePermResult?.success(granted)
                pendingBlePermResult = null
            }
            PERM_REQUEST_BG_LOC -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    Logger.info("permission_granted", feature = "geofence",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permission" to "ACCESS_BACKGROUND_LOCATION"))
                } else {
                    Logger.warn("permission_denied", feature = "geofence",
                        action = "onRequestPermissionsResult",
                        payload = mapOf("permission" to "ACCESS_BACKGROUND_LOCATION"))
                }
                pendingBgLocResult?.success(granted)
                pendingBgLocResult = null
            }
        }
    }

    // Detecta quando o app é aberto (ou trazido ao foreground) pelo botão flutuante.
    // FLAG_ACTIVITY_SINGLE_TOP garante que esta Activity não seja recriada,
    // mas onNewIntent() é chamado com o Intent atualizado.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("start_voice_recording", false)) {
            Logger.info("overlay_opened_app", feature = "overlay", action = "onNewIntent")
            overlayChannel?.invokeMethod("openVoiceFromOverlay", null)
        }
    }

    override fun onDestroy() {
        Logger.info("activity_destroying", feature = "main_activity", action = "onDestroy")
        stopLocationStream()
        stopBleAdvertising()
        stopBleScan()
        // Fecha todos os GATTs ativos para evitar leak de conexões
        val gattCount = activeGatts.size
        activeGatts.forEach { gatt ->
            try { gatt.disconnect(); gatt.close() } catch (e: Exception) {
                Logger.warn("gatt_cleanup_failed", feature = "ble",
                    action = "onDestroy", exception = e)
            }
        }
        if (gattCount > 0) {
            Logger.debug("gatt_connections_closed", feature = "ble", action = "onDestroy",
                payload = mapOf("count" to gattCount.toString()))
        }
        activeGatts.clear()
        mainHandler.removeCallbacksAndMessages(null)
        Logger.info("activity_destroyed", feature = "main_activity", action = "onDestroy")
        super.onDestroy()
    }
}
