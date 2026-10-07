package be.mapfollow.mapfollow

import android.Manifest
import android.content.pm.PackageManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

/** Notifications are requested only when the runner starts a real session. */
class MainActivity : FlutterActivity() {
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private lateinit var audioChannel: MethodChannel
    private var gnssSink: EventChannel.EventSink? = null
    private var gnssResumed = false
    private var gnssRegistered = false
    private var providerReceiverRegistered = false
    private val gnssHandler = Handler(Looper.getMainLooper())
    private val locationManager: LocationManager
        get() = getSystemService(LOCATION_SERVICE) as LocationManager
    private val providerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { refreshGnss() }
    }
    private val gnssCallback = object : GnssStatus.Callback() {
        override fun onStarted() {
            if (gnssRegistered && gnssResumed) emitGnssState("waiting")
        }
        override fun onStopped() {
            if (gnssRegistered && gnssResumed) emitGnssState("unavailable")
        }
        override fun onSatelliteStatusChanged(status: GnssStatus) {
            if (!gnssRegistered || !gnssResumed || gnssSink == null) return
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                refreshGnss()
                return
            }
            val counts = linkedMapOf<String, IntArray>()
            for (index in 0 until status.satelliteCount) {
                val code = when (status.getConstellationType(index)) {
                    GnssStatus.CONSTELLATION_GPS -> "GPS"
                    GnssStatus.CONSTELLATION_GLONASS -> "GLONASS"
                    GnssStatus.CONSTELLATION_GALILEO -> "Galileo"
                    GnssStatus.CONSTELLATION_BEIDOU -> "BeiDou"
                    GnssStatus.CONSTELLATION_QZSS -> "QZSS"
                    GnssStatus.CONSTELLATION_SBAS -> "SBAS"
                    // IRNSS vaut 7 depuis API 30 ; les appareils API 26 restent compatibles.
                    7 -> "IRNSS"
                    else -> "Unknown"
                }
                val count = counts.getOrPut(code) { intArrayOf(0, 0) }
                count[0]++
                if (status.usedInFix(index)) count[1]++
            }
            gnssSink?.success(mapOf(
                "availability" to "available", "observedAt" to System.currentTimeMillis(),
                "constellations" to counts.map { (code, count) ->
                    mapOf("code" to code, "seen" to count[0], "used" to count[1])
                }
            ))
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mapfollow/battery")
            .setMethodCallHandler { call, result ->
                if (call.method != "getSnapshot") {
                    result.notImplemented()
                } else {
                    try { result.success(batterySnapshot()) }
                    catch (_: RuntimeException) { result.success(null) }
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mapfollow/gnssStatus")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    gnssSink = events
                    refreshGnss()
                }
                override fun onCancel(arguments: Any?) {
                    gnssSink = null
                    stopGnss()
                    stopProviderReceiver()
                }
            })
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mapfollow/audio")
        audioChannel.setMethodCallHandler { call, result ->
            val manager = getSystemService(AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "requestFocus" -> {
                    audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
                    val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                        .setOnAudioFocusChangeListener({ change ->
                            if (change < 0) audioChannel.invokeMethod("interrupted", null)
                        }, Handler(Looper.getMainLooper()))
                        .build()
                    audioFocusRequest = request
                    result.success(manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
                }
                "abandonFocus" -> {
                    audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
                    audioFocusRequest = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mapfollow/permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestNotifications") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (pendingNotificationResult != null) {
                    result.error("busy", "Une autorisation est déjà en cours.", null)
                } else {
                    pendingNotificationResult = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 410)
                }
            }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 410) {
            pendingNotificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingNotificationResult = null
        }
        if (gnssSink != null) refreshGnss()
    }

    private fun batterySnapshot(): Map<String, Any?> {
        // Reading the sticky system broadcast does not register a listener.
        val snapshot = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val manager = getSystemService(BATTERY_SERVICE) as? BatteryManager
        val level = snapshot?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = snapshot?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = snapshot?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val temperature = snapshot?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val voltage = snapshot?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
        fun property(id: Int): Int? = try {
            manager?.getIntProperty(id)?.takeUnless { it == Int.MIN_VALUE }
        } catch (_: RuntimeException) { null }
        return mapOf(
            "levelPercent" to if (scale > 0 && level in 0..scale) (100.0 * level / scale).toInt() else null,
            "charging" to when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL -> true
                BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false
                else -> null
            },
            "temperatureC" to temperature?.takeUnless { it == Int.MIN_VALUE }?.div(10.0),
            "voltageMv" to voltage?.takeIf { it > 0 },
            "currentMicroAmps" to property(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
            "chargeMicroAh" to property(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)?.takeIf { it >= 0 }
        )
    }

    private fun emitGnssState(state: String) {
        gnssSink?.success(mapOf("availability" to state,
            "observedAt" to System.currentTimeMillis(), "constellations" to emptyList<Any>()))
    }

    private fun refreshGnss() {
        // Le diagnostic n'active pas le GPS et ne sollicite jamais de permission.
        if (gnssSink == null) return
        if (!gnssResumed) {
            stopGnss()
            emitGnssState("inactive")
            return
        }
        if (!providerReceiverRegistered) {
            val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION)
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(providerReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            else registerReceiver(providerReceiver, filter)
            providerReceiverRegistered = true
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            stopGnss()
            emitGnssState("permissionDenied")
            return
        }
        try {
            if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                stopGnss()
                emitGnssState("unavailable")
                return
            }
            if (!gnssRegistered) {
                gnssRegistered = locationManager.registerGnssStatusCallback(gnssCallback, gnssHandler)
                emitGnssState(if (gnssRegistered) "waiting" else "unavailable")
            }
        } catch (_: SecurityException) {
            stopGnss()
            emitGnssState("permissionDenied")
        } catch (_: RuntimeException) {
            stopGnss()
            emitGnssState("unavailable")
        }
    }

    private fun stopGnss() {
        val wasRegistered = gnssRegistered
        gnssRegistered = false
        if (wasRegistered) {
            try { locationManager.unregisterGnssStatusCallback(gnssCallback) }
            catch (_: RuntimeException) { /* Révocation système : aucun état sensible à journaliser. */ }
        }
    }

    private fun stopProviderReceiver() {
        if (providerReceiverRegistered) {
            unregisterReceiver(providerReceiver)
            providerReceiverRegistered = false
        }
    }

    override fun onResume() {
        super.onResume()
        gnssResumed = true
        refreshGnss()
    }

    override fun onPause() {
        gnssResumed = false
        stopGnss()
        stopProviderReceiver()
        emitGnssState("inactive")
        super.onPause()
    }

    override fun onDestroy() {
        gnssSink = null
        stopGnss()
        stopProviderReceiver()
        super.onDestroy()
    }
}
