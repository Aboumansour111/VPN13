package com.vpn13.vpn13_client

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import libv2ray.Libv2ray
import go.Seq
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        XrayVpnService.updateAppVisibility(true)
    }

    override fun onPause() {
        XrayVpnService.updateAppVisibility(false)
        super.onPause()
    }

    private val pingExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var pingEnvironmentInitialized = false

    private var permissionResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> requestVpnPermission(result)
                    "requestNotifications" -> requestNotificationPermission(result)
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
                                .putExtra(XrayVpnService.EXTRA_DNS, call.argument<String>("dnsAddress") ?: "1.1.1.1")
                                .putStringArrayListExtra(
                                    XrayVpnService.EXTRA_EXCLUDED_APPS,
                                    ArrayList(call.argument<List<String>>("excludedApps") ?: emptyList())
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
                    "measureOutboundDelay" -> {
                        val config = call.argument<String>("config")
                        val url = call.argument<String>("url") ?: "https://www.google.com/generate_204"
                        if (config.isNullOrBlank()) {
                            result.error("INVALID_CONFIG", "Xray config is empty", null)
                        } else {
                            pingExecutor.execute {
                                try {
                                    synchronized(this) {
                                        if (!pingEnvironmentInitialized) {
                                            Seq.setContext(applicationContext)
                                            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
                                            pingEnvironmentInitialized = true
                                        }
                                    }
                                    val delay = Libv2ray.measureOutboundDelay(config, url)
                                    mainHandler.post { result.success(delay) }
                                } catch (error: Exception) {
                                    mainHandler.post {
                                        result.error("PING_FAILED", error.message ?: "Xray delay test failed", null)
                                    }
                                }
                            }
                        }
                    }
                    "getApps" -> result.success(listInstalledApps())
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

    private fun listInstalledApps(): List<Map<String, String>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { resolve ->
                val pkg = resolve.activityInfo?.applicationInfo?.packageName ?: return@mapNotNull null
                if (pkg == packageName) return@mapNotNull null
                mapOf("package" to pkg, "label" to resolve.loadLabel(packageManager).toString())
            }
            .distinctBy { it["package"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("PERMISSION_PENDING", "Notification permission request is already pending", null)
            return
        }
        notificationPermissionResult = result
        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            notificationPermissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationPermissionResult = null
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "vpn13/xray"
        private const val EVENT_CHANNEL = "vpn13/xray/events"
        private const val REQUEST_VPN_PERMISSION = 7313
        private const val REQUEST_NOTIFICATION_PERMISSION = 7314
    }
}
