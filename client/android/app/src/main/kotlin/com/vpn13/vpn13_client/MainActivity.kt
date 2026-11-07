package com.vpn13.vpn13_client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import libv2ray.Libv2ray

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> requestVpnPermission(result)
                    "connect" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("INVALID_CONFIG", "Xray config is empty", null)
                        } else {
                            val intent = Intent(this, XrayVpnService::class.java)
                                .setAction(XrayVpnService.ACTION_START)
                                .putExtra(XrayVpnService.EXTRA_CONFIG, config)
                                .putExtra(
                                    XrayVpnService.EXTRA_PROFILE_NAME,
                                    call.argument<String>("profileName") ?: "VPN13"
                                )
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    startForegroundService(intent)
                                } else {
                                    startService(intent)
                                }
                                result.success(true)
                            } catch (error: Exception) {
                                result.error("SERVICE_START_FAILED", error.message, null)
                            }
                        }
                    }
                    "disconnect" -> {
                        val intent = Intent(this, XrayVpnService::class.java)
                            .setAction(XrayVpnService.ACTION_STOP)
                        try {
                            startService(intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("SERVICE_STOP_FAILED", error.message, null)
                        }
                    }
                    "getStatus" -> result.success(XrayVpnService.statusSnapshot())
                    "getVersion" -> {
                        try {
                            result.success(Libv2ray.checkVersionX())
                        } catch (error: Exception) {
                            result.error("XRAY_VERSION_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    XrayVpnService.eventSink = events
                    events?.success(XrayVpnService.statusSnapshot())
                }

                override fun onCancel(arguments: Any?) {
                    XrayVpnService.eventSink = null
                }
            })
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("PERMISSION_PENDING", "VPN permission request is already pending", null)
            return
        }
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        permissionResult = result
        try {
            startActivityForResult(intent, REQUEST_VPN_PERMISSION)
        } catch (error: Exception) {
            permissionResult = null
            result.error("PERMISSION_REQUEST_FAILED", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android, retained for Flutter VPN permission flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            permissionResult?.success(resultCode == Activity.RESULT_OK)
            permissionResult = null
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "vpn13/xray"
        private const val EVENT_CHANNEL = "vpn13/xray/events"
        private const val REQUEST_VPN_PERMISSION = 7313
    }
}
