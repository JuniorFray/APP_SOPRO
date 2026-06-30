package com.sopro.sopro

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
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

    // ═════════════════════════════════════════════════════════════════════════
    // Inicialização dos canais Flutter ↔ Native
    // ═════════════════════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fusedClient       = LocationServices.getFusedLocationProviderClient(this)
        geofencingClient  = LocationServices.getGeofencingClient(this)

        // ── GPS: MethodChannel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission"    -> result.success(hasLocationPermission())
                    "requestPermission"  -> requestLocationPermission(result)
                    "getCurrentPosition" -> getCurrentPosition(result)
                    else                 -> result.notImplemented()
                }
            }

        // ── GPS: EventChannel (stream contínuo de posição) ────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    locationEventSink = events
                    startLocationStream()
                }
                override fun onCancel(args: Any?) {
                    stopLocationStream()
                    locationEventSink = null
                }
            })

        // ── BLE: MethodChannel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermissions"    -> result.success(hasBluetoothPermissions())
                    "requestPermissions"  -> requestBluetoothPermissions(result)
                    "startAdvertising"    -> {
                        val cardJson = call.argument<String>("cardJson") ?: "{}"
                        // txPower: 0=ULTRA_LOW, 1=LOW (padrão), 2=MEDIUM, 3=HIGH
                        val txPower = call.argument<Int>("txPower") ?: 1
                        startBleAdvertising(cardJson, txPower, result)
                    }
                    "stopAdvertising"     -> { stopBleAdvertising(); result.success(null) }
                    "getAdapterState"     -> result.success(getAdapterState())
                    "connectAndReadCard"  -> {
                        val deviceId = call.argument<String>("deviceId") ?: ""
                        connectAndReadCard(deviceId, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── BLE: EventChannel (stream de resultados do scan) ──────────────────
        // Padrão espelhando o GPS stream: onListen inicia o scan, onCancel o para.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_SCAN_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    scanEventSink = events
                    startBleScan()
                }
                override fun onCancel(args: Any?) {
                    stopBleScan()
                    scanEventSink = null
                }
            })

        // ── Geofencing nativo: MethodChannel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEOFENCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "addGeofence" -> {
                        val id     = call.argument<String>("id")     ?: return@setMethodCallHandler
                        val lat    = call.argument<Double>("lat")    ?: return@setMethodCallHandler
                        val lng    = call.argument<Double>("lng")    ?: return@setMethodCallHandler
                        val radius = call.argument<Double>("radius") ?: return@setMethodCallHandler
                        val name   = call.argument<String>("name")   ?: id
                        addNativeGeofence(id, lat, lng, radius.toFloat(), name, result)
                    }
                    "removeGeofence" -> {
                        val id = call.argument<String>("id") ?: return@setMethodCallHandler
                        geofencingClient.removeGeofences(listOf(id))
                            .addOnSuccessListener {
                                // Remove também o nome salvo nas prefs
                                getSharedPreferences(PREFS_GEOFENCE_NAMES, MODE_PRIVATE)
                                    .edit().remove(id).apply()
                                result.success(null)
                            }
                            .addOnFailureListener { e ->
                                result.error("REMOVE_FAILED", e.message, null)
                            }
                    }
                    "clearGeofences" -> {
                        val pi = geofencePendingIntent
                        if (pi != null) {
                            geofencingClient.removeGeofences(pi)
                                .addOnSuccessListener {
                                    getSharedPreferences(PREFS_GEOFENCE_NAMES, MODE_PRIVATE)
                                        .edit().clear().apply()
                                    result.success(null)
                                }
                                .addOnFailureListener { e ->
                                    result.error("CLEAR_FAILED", e.message, null)
                                }
                        } else {
                            result.success(null) // nenhum geofence registrado ainda
                        }
                    }
                    "hasBackgroundLocationPermission" ->
                        result.success(hasBackgroundLocationPermission())
                    "requestBackgroundLocationPermission" ->
                        requestBackgroundLocationPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // GPS — permissão + posição pontual + stream
    // ═════════════════════════════════════════════════════════════════════════

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) { result.success(true); return }
        pendingLocPermResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), PERM_REQUEST_LOC
        )
    }

    private fun getCurrentPosition(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null); return
        }
        fusedClient?.lastLocation
            ?.addOnSuccessListener { loc ->
                if (loc != null) result.success(locationMap(loc))
                else requestFreshLocation(result)
            }
            ?.addOnFailureListener { e -> result.error("LOCATION_ERROR", e.message, null) }
    }

    private fun requestFreshLocation(result: MethodChannel.Result) {
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 0L)
            .setMaxUpdates(1).build()
        var done = false
        fusedClient?.requestLocationUpdates(req, object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                if (done) return
                done = true
                fusedClient?.removeLocationUpdates(this)
                val loc = lr.lastLocation
                if (loc != null) result.success(locationMap(loc))
                else result.error("NULL_LOCATION", "Could not obtain location", null)
            }
        }, Looper.getMainLooper())
    }

    private fun startLocationStream() {
        if (!hasLocationPermission()) return
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2_000L)
            .setMinUpdateDistanceMeters(10f).build()
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                lr.lastLocation?.let { locationEventSink?.success(locationMap(it)) }
            }
        }
        fusedClient?.requestLocationUpdates(req, locationCallback!!, Looper.getMainLooper())
    }

    private fun stopLocationStream() {
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
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "ACCESS_FINE_LOCATION required", null)
            return
        }

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
                result.success(null)
            }
            .addOnFailureListener { e ->
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
        if (hasBackgroundLocationPermission()) { result.success(true); return }
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
        if (hasBluetoothPermissions()) { result.success(true); return }
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
        if (!hasBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null); return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is not enabled", null); return
        }

        currentCardJson = cardJson
        setupGattServer(btManager)

        advertiser = btAdapter.bluetoothLeAdvertiser
        if (advertiser == null) {
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
                if (!responded) { responded = true; result.success(true) }
            }
            override fun onStartFailure(errorCode: Int) {
                if (!responded) { responded = true
                    result.error("ADVERTISE_FAILED", "Error code: $errorCode", null)
                }
            }
        })
    }

    private fun stopBleAdvertising() {
        try { advertiser?.stopAdvertising(object : AdvertiseCallback() {}) } catch (_: Exception) {}
        advertiser = null
        try { gattServer?.close() } catch (_: Exception) {}
        gattServer = null
    }

    // GATT server: responde leituras da characteristic de ContextCard.
    // Suporta Long Read (offset incremental) para payloads maiores que o MTU negociado.
    private fun setupGattServer(btManager: BluetoothManager) {
        try { gattServer?.close() } catch (_: Exception) {}

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
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE Central — scan (EventChannel) + GATT client (connectAndReadCard)
    // ═════════════════════════════════════════════════════════════════════════

    // Inicia scan BLE filtrando apenas dispositivos com o SERVICE_UUID Sopro.
    // Resultados são emitidos via scanEventSink (EventChannel) para o Dart.
    private fun startBleScan() {
        if (!hasBluetoothPermissions()) {
            scanEventSink?.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            scanEventSink?.error("BT_DISABLED", "Bluetooth is not enabled", null)
            return
        }

        scanner = btAdapter.bluetoothLeScanner
        if (scanner == null) {
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
                // ScanCallback pode ser chamado de thread de fundo — garante main thread
                mainHandler.post { scanEventSink?.success(info) }
            }
            override fun onScanFailed(errorCode: Int) {
                mainHandler.post {
                    scanEventSink?.error("SCAN_FAILED", "Error code: $errorCode", null)
                }
            }
        }

        scanner?.startScan(listOf(filter), settings, scanCallback!!)
    }

    private fun stopBleScan() {
        try { scanCallback?.let { scanner?.stopScan(it) } } catch (_: Exception) {}
        scanCallback = null
        scanner = null
    }

    // Conecta ao dispositivo como cliente GATT, lê o ContextCard e desconecta.
    // Retorna o JSON do ContextCard via MethodChannel result.
    // Timeout de GATT_TIMEOUT_MS para evitar que a Promise fique pendente para sempre.
    private fun connectAndReadCard(deviceId: String, result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null); return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is not enabled", null); return
        }

        val device = try {
            btAdapter.getRemoteDevice(deviceId)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ID", "Invalid device ID: $deviceId", null); return
        }

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
            try { gatt.disconnect() } catch (_: Exception) {}
            mainHandler.postDelayed({
                try { gatt.close() } catch (_: Exception) {}
                activeGatts.remove(gatt)
            }, 500L) // pequeno delay para que o disconnect seja processado
        }

        // Timeout: se nenhuma resposta chegar em GATT_TIMEOUT_MS, falha graciosamente
        val timeoutRunnable = Runnable {
            respond { result.error("TIMEOUT", "GATT connection timed out", null) }
            activeGatt?.let { cleanup(it) }
        }
        mainHandler.postDelayed(timeoutRunnable, GATT_TIMEOUT_MS)

        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        // Solicita MTU maior para suportar ContextCards de até 512 bytes
                        gatt.requestMtu(512)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        respond { result.error("DISCONNECTED", "Device disconnected (status=$status)", null) }
                        try { gatt.close() } catch (_: Exception) {}
                        activeGatts.remove(gatt)
                    }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                // Inicia descoberta de serviços após negociar MTU
                gatt.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    respond { result.error("DISCOVERY_FAILED", "Service discovery failed: $status", null) }
                    cleanup(gatt); return
                }
                val service = gatt.getService(UUID.fromString("550e8400-e29b-41d4-a716-446655440000"))
                if (service == null) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    respond { result.error("NO_SERVICE", "Sopro service not found", null) }
                    cleanup(gatt); return
                }
                val char = service.getCharacteristic(CONTEXT_CARD_CHAR_UUID)
                if (char == null) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    respond { result.error("NO_CHAR", "ContextCard characteristic not found", null) }
                    cleanup(gatt); return
                }
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
                    respond { res.success(cardJson) }
                } else {
                    respond { res.error("READ_FAILED", "Characteristic read failed: $status", null) }
                }
                cleanup(gatt)
            }
        }

        // Conecta com preferência por BLE (TRANSPORT_LE) — disponível a partir do API 23
        activeGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        activeGatts.add(activeGatt)
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
                pendingLocPermResult?.success(granted)
                pendingLocPermResult = null
                if (granted && locationEventSink != null) startLocationStream()
            }
            PERM_REQUEST_BLE -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                pendingBlePermResult?.success(granted)
                pendingBlePermResult = null
            }
            PERM_REQUEST_BG_LOC -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingBgLocResult?.success(granted)
                pendingBgLocResult = null
            }
        }
    }

    override fun onDestroy() {
        stopLocationStream()
        stopBleAdvertising()
        stopBleScan()
        // Fecha todos os GATTs ativos para evitar leak de conexões
        activeGatts.forEach { try { it.disconnect(); it.close() } catch (_: Exception) {} }
        activeGatts.clear()
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
