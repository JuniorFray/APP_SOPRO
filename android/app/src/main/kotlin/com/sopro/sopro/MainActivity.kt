package com.sopro.sopro

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
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

// MainActivity expõe GPS e BLE Social ao Flutter via canais nativos.
//
// ── GPS (Sprint 5) ──────────────────────────────────────────────────────────
// MethodChannel "com.sopro.sopro/location":
//   checkPermission / requestPermission / getCurrentPosition
// EventChannel "com.sopro.sopro/location_stream":
//   Stream de posição a cada 5s / 10m
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
        fusedClient = LocationServices.getFusedLocationProviderClient(this)

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
                        startBleAdvertising(cardJson, result)
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

    private fun startBleAdvertising(cardJson: String, result: MethodChannel.Result) {
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
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
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

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
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
