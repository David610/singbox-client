package app.singboxclient.vpn_core

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener

private const val METHOD_CHANNEL = "vpn_core/methods"
private const val EVENT_CHANNEL = "vpn_core/status"
private const val VPN_PERMISSION_REQUEST_CODE = 0x5B0C

/**
 * The entire native Android surface of vpn_core. Deliberately thin: this
 * class only (a) requests the Android VPN permission dialog, and
 * (b) forwards typed calls to [SingBoxVpnService]. All sing-box/libbox
 * interaction happens inside the service, never here, so the service can
 * keep running (and this plugin/Activity can be torn down and recreated)
 * independently -- matching how android.net.VpnService is meant to be used.
 */
class VpnCorePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val context = applicationContext ?: return result.error(
            "no_context", "plugin not attached", null,
        )
        when (call.method) {
            "initialize" -> {
                SingBoxVpnService.initialize(context)
                result.success(null)
            }

            "start" -> {
                val tag = call.argument<String>("tag")
                val configJson = call.argument<String>("configJson")
                if (tag == null || configJson == null) {
                    return result.error("bad_args", "tag and configJson are required", null)
                }
                startWithPermission(context, tag, configJson, result)
            }

            "stop" -> {
                context.startService(
                    Intent(context, SingBoxVpnService::class.java)
                        .setAction(SingBoxVpnService.ACTION_STOP),
                )
                result.success(null)
            }

            "restart" -> {
                val tag = call.argument<String>("tag")
                val configJson = call.argument<String>("configJson")
                if (tag == null || configJson == null) {
                    return result.error("bad_args", "tag and configJson are required", null)
                }
                // VpnService.Builder.establish() atomically replaces the
                // previous tun interface, so a plain start with a new
                // config is a restart -- no separate stop() needed and no
                // user-visible disconnect flicker.
                startWithPermission(context, tag, configJson, result)
            }

            "status" -> result.success(SingBoxVpnService.currentStatus().toWire())

            "coreVersion" -> result.success(SingBoxVpnService.coreVersion())

            "getSanitizedLogs" -> {
                val maxLines = call.argument<Int>("maxLines") ?: 200
                result.success(SingBoxVpnService.sanitizedLogs(maxLines))
            }

            else -> result.notImplemented()
        }
    }

    private fun startWithPermission(context: Context, tag: String, configJson: String, result: Result) {
        val permissionIntent = VpnService.prepare(context)
        if (permissionIntent == null) {
            // Already granted.
            SingBoxVpnService.start(context, tag, configJson)
            return result.success(null)
        }
        val act = activity
        if (act == null) {
            return result.error(
                "no_activity",
                "VPN permission has not been granted yet and no Activity is attached to request it",
                null,
            )
        }
        pendingPermissionResult = result
        act.startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST_CODE)
        // Actual start() happens in onActivityResult once the user answers
        // the system VPN consent dialog; see below.
        pendingStart = Pair(tag, configJson)
    }

    private var pendingStart: Pair<String, String>? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) return false
        val result = pendingPermissionResult
        pendingPermissionResult = null
        val start = pendingStart
        pendingStart = null
        val context = applicationContext

        if (resultCode != Activity.RESULT_OK || context == null || start == null) {
            result?.error("permission_denied", "user declined the VPN permission prompt", null)
            return true
        }
        SingBoxVpnService.start(context, start.first, start.second)
        result?.success(null)
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        SingBoxVpnService.addStatusListener { status -> events.success(status.toWire()) }
    }

    override fun onCancel(arguments: Any?) {
        SingBoxVpnService.clearStatusListener()
    }
}
