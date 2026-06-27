package com.sopro.sopro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// MainActivity expõe GPS nativo ao Flutter via dois canais:
//
// MethodChannel "com.sopro.sopro/location":
//   - checkPermission()       → Boolean
//   - requestPermission()     → Boolean (aguarda resultado do diálogo do sistema)
//   - getCurrentPosition()    → Map {latitude, longitude, accuracy}
//
// EventChannel "com.sopro.sopro/location_stream":
//   - Emite Map {latitude, longitude, accuracy} a cada 5 s ou 10 m de deslocamento
//
// Usa FusedLocationProviderClient (Google Play Services) — API padrão Android para GPS
// eficiente em bateria. Não requer nenhum pacote Flutter externo.
class MainActivity : FlutterActivity() {

    companion object {
        private const val LOCATION_CHANNEL = "com.sopro.sopro/location"
        private const val STREAM_CHANNEL   = "com.sopro.sopro/location_stream"
        private const val PERM_REQUEST     = 1001
    }

    private var fusedClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var eventSink: EventChannel.EventSink? = null

    // Armazena o Result pendente enquanto o diálogo de permissão está aberto
    private var pendingPermResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fusedClient = LocationServices.getFusedLocationProviderClient(this)

        // Canal de métodos — permissão e posição pontual
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission"     -> result.success(hasPermission())
                    "requestPermission"   -> requestPermission(result)
                    "getCurrentPosition"  -> getCurrentPosition(result)
                    else                  -> result.notImplemented()
                }
            }

        // Canal de eventos — stream contínuo de posição
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startStream()
                }
                override fun onCancel(args: Any?) {
                    stopStream()
                    eventSink = null
                }
            })
    }

    // --- Permissão ---

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) { result.success(true); return }
        pendingPermResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
            PERM_REQUEST
        )
    }

    // Chamado pelo Android quando o usuário responde ao diálogo de permissão
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERM_REQUEST) return

        val granted = grantResults.isNotEmpty() &&
                      grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermResult?.success(granted)
        pendingPermResult = null

        // Se concedida enquanto o stream estava aguardando, inicia-o agora
        if (granted && eventSink != null) startStream()
    }

    // --- Posição pontual ---

    private fun getCurrentPosition(result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }
        fusedClient?.lastLocation
            ?.addOnSuccessListener { loc ->
                if (loc != null) {
                    result.success(locationMap(loc))
                } else {
                    // lastLocation pode ser null em dispositivos recém-ligados
                    requestFresh(result)
                }
            }
            ?.addOnFailureListener { e ->
                result.error("LOCATION_ERROR", e.message, null)
            }
    }

    // Solicita uma leitura fresca quando lastLocation é null
    private fun requestFresh(result: MethodChannel.Result) {
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 0L)
            .setMaxUpdates(1)
            .build()
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

    // --- Stream contínuo ---

    private fun startStream() {
        if (!hasPermission()) return
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
            .setMinUpdateDistanceMeters(10f)
            .build()
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(lr: LocationResult) {
                lr.lastLocation?.let { eventSink?.success(locationMap(it)) }
            }
        }
        fusedClient?.requestLocationUpdates(req, locationCallback!!, Looper.getMainLooper())
    }

    private fun stopStream() {
        locationCallback?.let { fusedClient?.removeLocationUpdates(it) }
        locationCallback = null
    }

    private fun locationMap(loc: android.location.Location) = mapOf(
        "latitude"  to loc.latitude,
        "longitude" to loc.longitude,
        "accuracy"  to loc.accuracy.toDouble()
    )

    override fun onDestroy() {
        stopStream()
        super.onDestroy()
    }
}
