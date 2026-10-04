package be.mapfollow.mapfollow

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Notifications are requested only when the runner starts a real session. */
class MainActivity : FlutterActivity() {
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private lateinit var audioChannel: MethodChannel
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}
