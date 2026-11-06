package com.vpn13.vpn13_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.Settings
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import go.Seq
import java.util.concurrent.Executors

class XrayVpnService : VpnService(), CoreCallbackHandler {
    @Volatile private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var controller: CoreController? = null
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var stopping = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    publish("error", "کانفیگ Xray خالی است")
                    stopSelf()
                    return START_NOT_STICKY
                }
                stopping = false
                startForeground(NOTIFICATION_ID, buildNotification())
                worker.execute { startTunnel(config) }
                return START_NOT_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun startTunnel(config: String) {
        try {
            stopCoreAndTunnel()
            publish("connecting", "در حال راه‌اندازی هسته Xray")
            val builder = Builder()
                .setSession("VPN13")
                .setMtu(1500)
                .addAddress("10.13.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addAddress("fd13:13::1", 126)
                .addRoute("::", 0)
                .addDnsServer("2606:4700:4700::1111")

            val established = builder.establish()
                ?: throw IllegalStateException("Android did not establish the VPN interface")
            tunnel = established

            Seq.setContext(applicationContext)
            val deviceId = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ANDROID_ID
            ).orEmpty()
            Libv2ray.initCoreEnv(filesDir.absolutePath, deviceId)
            val core = Libv2ray.newCoreController(this)
            controller = core
            core.startLoop(config, established.fd)

            if (!core.isRunning) {
                throw IllegalStateException("Xray core did not enter running state")
            }
            publish("connected", "هسته Xray فعال شد")
        } catch (error: Exception) {
            publish("error", error.message ?: error.javaClass.simpleName)
            stopCoreAndTunnel()
            stopSelf()
        }
    }

    private fun stopCoreAndTunnel() {
        stopping = true
        try {
            controller?.let { core ->
                if (core.isRunning) core.stopLoop()
            }
        } catch (error: Exception) {
            publish("error", "خطا در توقف هسته: ${error.message}")
        } finally {
            controller = null
            try {
                tunnel?.close()
            } catch (_: Exception) {
            }
            tunnel = null
            XrayVpnService.publish("disconnected", "اتصال قطع شد")
        }
    }

    override fun onRevoke() {
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopping = true
        try {
            worker.execute { stopCoreAndTunnel() }
            worker.shutdown()
            worker.awaitTermination(3, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: Exception) {
            try {
                controller?.stopLoop()
            } catch (_: Exception) {
            }
            try {
                tunnel?.close()
            } catch (_: Exception) {
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun startup(): Long {
        publish("connected", "هسته Xray شروع شد")
        return 0L
    }

    override fun shutdown(): Long {
        publish("disconnected", "هسته Xray متوقف شد")
        return 0L
    }

    override fun onEmitStatus(code: Long, message: String?): Long {
        if (!message.isNullOrBlank()) {
            publish(if (code == 0L) "message" else "error", message)
        }
        return 0L
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VPN13 connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN13 active tunnel status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val pending = openApp?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("VPN13")
            .setContentText("تونل VPN فعال است")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(pending)
            .build()
    }

    private fun publish(state: String, message: String) {
        publishEvent(state, message)
    }

    companion object {
        const val ACTION_START = "com.vpn13.vpn13_client.action.START_XRAY"
        const val ACTION_STOP = "com.vpn13.vpn13_client.action.STOP_XRAY"
        const val EXTRA_CONFIG = "xray_config"
        private const val CHANNEL_ID = "vpn13_xray"
        private const val NOTIFICATION_ID = 1313

        @Volatile var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        @Volatile private var currentState = "disconnected"
        @Volatile private var currentMessage = "آماده اتصال"

        fun statusSnapshot(): Map<String, Any> = mapOf(
            "state" to currentState,
            "message" to currentMessage
        )

        private fun publishEvent(state: String, message: String) {
            currentState = state
            currentMessage = message
            eventSink?.success(statusSnapshot())
        }
    }
}
