package com.sopro.sopro

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.pm.PackageManager
import android.os.Build
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

// MainActivity expõe dois grupos de canais nativos ao Flutter:
//
// ── GPS (Sprint 5) ──────────────────────────────────────────────────────────
// MethodChannel "com.sopro.sopro/location":
//   checkPermission()       → Boolean
//   requestPermission()     → Boolean (aguarda diálogo do sistema)
//   getCurrentPosition()    → Map {latitude, longitude, accuracy}
// EventChannel "com.sopro.sopro/location_stream":
//   Emite Map {latitude, longitude, accuracy} a cada 5s / 10m
//
// ── BLE Social (Sprint 7) ───────────────────────────────────────────────────
// MethodChannel "com.sopro.sopro/ble":
//   checkPermissions()                   → Boolean
//   requestPermissions()                 → Boolean
//   startAdvertising({cardJson:String})  → Boolean
//   stopAdvertising()                    → void
//
// O advertising ativa BluetoothLeAdvertiser com o SERVICE_UUID Sopro.
// Um BluetoothGattServer expõe a characteristic CONTEXT_CARD_CHAR_UUID,
// que retorna o ContextCard do usuário em JSON UTF-8 para quem conectar.
class MainActivity : FlutterActivity() {

    companion object {
        // ── GPS ───────────────────────────────────────────────────────────────
        private const val LOCATION_CHANNEL  = "com.sopro.sopro/location"
        private const val STREAM_CHANNEL    = "com.sopro.sopro/location_stream"
        private const val PERM_REQUEST_LOC  = 1001

        // ── BLE ───────────────────────────────────────────────────────────────
        private const val BLE_CHANNEL       = "com.sopro.sopro/ble"
        private const val PERM_REQUEST_BLE  = 1002

        // UUIDs do serviço Sopro — FIXOS (nunca alterar; identificam o app na rede BLE)
        private val SERVICE_UUID           = ParcelUuid.fromString("550e8400-e29b-41d4-a716-446655440000")
        private val CONTEXT_CARD_CHAR_UUID = UUID.fromString("550e8401-e29b-41d4-a716-446655440000")
    }

    // ── Campos GPS ────────────────────────────────────────────────────────────
    private var fusedClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingLocPermResult: MethodChannel.Result? = null

    // ── Campos BLE ────────────────────────────────────────────────────────────
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var currentCardJson: String = "{}"
    private var pendingBlePermResult: MethodChannel.Result? = null

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
                    eventSink = events
                    startLocationStream()
                }
                override fun onCancel(args: Any?) {
                    stopLocationStream()
                    eventSink = null
                }
            })

        // ── BLE: MethodChannel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermissions"   -> result.success(hasBluetoothPermissions())
                    "requestPermissions" -> requestBluetoothPermissions(result)
                    "startAdvertising"   -> {
                        val cardJson = call.argument<String>("cardJson") ?: "{}"
                        startBleAdvertising(cardJson, result)
                    }
                    "stopAdvertising"    -> { stopBleAdvertising(); result.success(null) }
                    else                 -> result.notImplemented()
                }
            }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // GPS — permissão
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

    // ═════════════════════════════════════════════════════════════════════════
    // GPS — posição pontual e stream
    // ═════════════════════════════════════════════════════════════════════════

    private fun getCurrentPosition(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }
        fusedClient?.lastLocation
            ?.addOnSuccessListener { loc ->
                if (loc != null) result.success(locationMap(loc))
                else requestFreshLocation(result)
            }
            ?.addOnFailureListener { e ->
                result.error("LOCATION_ERROR", e.message, null)
            }
    }

    // Solicita leitura fresca quando lastLocation é null (dispositivo recém-ligado)
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
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
            .setMinUpdateDistanceMeters(10f).build()
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                lr.lastLocation?.let { eventSink?.success(locationMap(it)) }
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
    // BLE — permissões
    // ═════════════════════════════════════════════════════════════════════════

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+): cada operação BLE requer permissão própria
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)      == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)   == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android < 12: ACCESS_FINE_LOCATION é suficiente para BLE scan/advertising
            hasLocationPermission()
        }
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
            // Em versões antigas, localização já cobre o BLE
            requestLocationPermission(result)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE — advertising + GATT server
    // ═════════════════════════════════════════════════════════════════════════

    private fun startBleAdvertising(cardJson: String, result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        val btManager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is not enabled", null)
            return
        }

        // Prepara o GATT server antes de iniciar o advertising para que dispositivos
        // que conectarem imediatamente já encontrem o serviço disponível
        currentCardJson = cardJson
        setupGattServer(btManager)

        advertiser = btAdapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("NO_ADVERTISER", "Device does not support BLE advertising", null)
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true)   // conectável para permitir leitura GATT do ContextCard
            .setTimeout(0)          // fica ativo até stopAdvertising() ser chamado
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        // Pacote de advertising: apenas o SERVICE_UUID Sopro.
        // O ContextCard completo é transferido via GATT após a conexão do dispositivo curioso.
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
                if (!responded) {
                    responded = true
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

    // Abre um BluetoothGattServer com o serviço Sopro.
    // Quando outro dispositivo conecta e lê CONTEXT_CARD_CHAR_UUID, recebe o
    // ContextCard do usuário em JSON UTF-8.
    // Suporta Long Read (offset incremental) para payloads maiores que o MTU.
    private fun setupGattServer(btManager: BluetoothManager) {
        try { gattServer?.close() } catch (_: Exception) {}

        gattServer = btManager.openGattServer(this, object : BluetoothGattServerCallback() {
            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                if (characteristic.uuid != CONTEXT_CARD_CHAR_UUID) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                    return
                }
                val bytes = currentCardJson.toByteArray(Charsets.UTF_8)
                if (offset > bytes.size) {
                    gattServer?.sendResponse(device, requestId,
                        BluetoothGatt.GATT_INVALID_OFFSET, 0, null)
                    return
                }
                // Envia o trecho a partir do offset (suporte a múltiplos Read Long)
                val chunk = bytes.copyOfRange(offset, bytes.size)
                gattServer?.sendResponse(device, requestId,
                    BluetoothGatt.GATT_SUCCESS, offset, chunk)
            }

            override fun onConnectionStateChange(
                device: BluetoothDevice, status: Int, newState: Int
            ) {
                // Sprint 7: sem estado adicional de conexão necessário
            }
        })

        val service = BluetoothGattService(
            UUID.fromString("550e8400-e29b-41d4-a716-446655440000"),
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        val characteristic = BluetoothGattCharacteristic(
            CONTEXT_CARD_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(characteristic)
        gattServer?.addService(service)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Permissões — callback unificado (requestCode distingue GPS de BLE)
    // ═════════════════════════════════════════════════════════════════════════

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            PERM_REQUEST_LOC -> {
                val granted = grantResults.isNotEmpty() &&
                              grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingLocPermResult?.success(granted)
                pendingLocPermResult = null
                // Reinicia o stream de GPS caso tenha ficado aguardando permissão
                if (granted && eventSink != null) startLocationStream()
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
        super.onDestroy()
    }
}
