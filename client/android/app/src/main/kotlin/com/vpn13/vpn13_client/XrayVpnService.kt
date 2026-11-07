package com.vpn13.vpn13_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import go.Seq
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class XrayVpnService : VpnService(), CoreCallbackHandler {
    @Volatile private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var controller: CoreController? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val statsWorker = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var statsTask: ScheduledFuture<*>? = null
    @Volatile private var lastUploadSample = 0L
    @Volatile private var lastDownloadSample = 0L
    @Volatile private var lastStatsSampleNanos = 0L
    @Volatile private var profileName = "VPN13"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                publish("disconnecting", "در حال قطع اتصال")
                worker.execute {
                    stopCoreAndTunnel()
                    mainHandler.post {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            stopForeground(STOP_FOREGROUND_REMOVE)
                        } else {
                            @Suppress("DEPRECATION")
                            stopForeground(true)
                        }
                        stopSelfResult(startId)
                    }
                }
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    publish("error", "کانفیگ Xray خالی است")
                    stopSelf()
                    return START_NOT_STICKY
                }
                profileName = intent.getStringExtra(EXTRA_PROFILE_NAME)?.takeIf { it.isNotBlank() } ?: "VPN13"
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
                .setSession(profileName)
                .setMtu(1500)
                .addAddress("10.13.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addAddress("fd13:13::1", 126)
                .addRoute("::", 0)
                .addDnsServer("2606:4700:4700::1111")
                .addDisallowedApplication(packageName)

            val established = builder.establish()
                ?: throw IllegalStateException("Android did not establish the VPN interface")
            tunnel = established

            Seq.setContext(applicationContext)
            // Let Xray generate and retain its own cryptographically random
            // 32-byte XUDP base key. Android ID is not a valid Base64URL key.
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            val core = Libv2ray.newCoreController(this)
            controller = core
            core.startLoop(config, established.fd)

            if (!core.isRunning) {
                throw IllegalStateException("Xray core did not enter running state")
            }
            startStatsPolling(core)
            publish("connected", "هسته Xray فعال شد")
        } catch (error: Exception) {
            publish("error", error.message ?: error.javaClass.simpleName)
            stopCoreAndTunnel()
            stopSelf()
        }
    }

    private fun stopCoreAndTunnel() {
        stopStatsPolling()
        try {
            controller?.let { core ->
                if (core.isRunning) core.stopLoop()
            }
        } catch (error: Exception) {
            publish("error", "خطا در توقف هسته: ${error.message}")
        } finally {
            controller = null
            currentUploadSpeed = 0L
            currentDownloadSpeed = 0L
            currentUploadTotal = 0L
            currentDownloadTotal = 0L
            try {
                tunnel?.close()
            } catch (_: Exception) {
            }
            tunnel = null
            publish("disconnected", "اتصال قطع شد")
        }
    }

    override fun onRevoke() {
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        try {
            if (!worker.isShutdown) {
                worker.execute { stopCoreAndTunnel() }
                worker.shutdown()
                worker.awaitTermination(5, TimeUnit.SECONDS)
            } else {
                stopCoreAndTunnel()
            }
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
        statsWorker.shutdownNow()
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
            .setContentTitle(profileName)
            .setContentText("تونل VPN فعال است")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pending)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "قطع اتصال",
                PendingIntent.getService(
                    this,
                    1314,
                    Intent(this, XrayVpnService::class.java).setAction(ACTION_STOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()
    }

    private fun startStatsPolling(core: CoreController) {
        stopStatsPolling()
        currentUploadSpeed = 0L
        currentDownloadSpeed = 0L
        currentUploadTotal = 0L
        currentDownloadTotal = 0L
        lastUploadSample = 0L
        lastDownloadSample = 0L
        lastStatsSampleNanos = System.nanoTime()
        statsTask = statsWorker.scheduleWithFixedDelay({
            if (controller !== core || !core.isRunning) return@scheduleAtFixedRate
            try {
                var uploaded = 0L
                var downloaded = 0L
                core.queryAllOutboundTrafficStats().split(';').forEach { entry ->
                    if (entry.isBlank()) return@forEach
                    val parts = entry.split(',', limit = 3)
                    if (parts.size != 3 || parts[0] == "blocked") return@forEach
                    val bytes = parts[2].toLongOrNull() ?: return@forEach
                    when (parts[1]) {
                        "uplink" -> uploaded += bytes
                        "downlink" -> downloaded += bytes
                    }
                }
                // Xray reports cumulative byte counters. Derive per-second
                // rates from the difference instead of treating totals as rates.
                val nowNanos = System.nanoTime()
                val elapsedSeconds = ((nowNanos - lastStatsSampleNanos).coerceAtLeast(1L)) / 1_000_000_000.0
                currentUploadSpeed = ((uploaded - lastUploadSample).coerceAtLeast(0L) / elapsedSeconds).toLong()
                currentDownloadSpeed = ((downloaded - lastDownloadSample).coerceAtLeast(0L) / elapsedSeconds).toLong()
                lastStatsSampleNanos = nowNanos
                currentUploadTotal = uploaded
                currentDownloadTotal = downloaded
                lastUploadSample = uploaded
                lastDownloadSample = downloaded
                publishEvent(currentState, currentMessage)
            } catch (_: Exception) {
                // Stats polling must not interrupt an active VPN session.
            }
        }, 5, 5, TimeUnit.SECONDS)
    }

    private fun stopStatsPolling() {
        statsTask?.cancel(false)
        statsTask = null
    }

    private fun publish(state: String, message: String) {
        publishEvent(state, message)
        if (state == "connected" || state == "disconnecting") {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification())
        }
    }

    companion object {
        const val ACTION_START = "com.vpn13.vpn13_client.action.START_XRAY"
        const val ACTION_STOP = "com.vpn13.vpn13_client.action.STOP_XRAY"
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_PROFILE_NAME = "profile_name"
        private const val CHANNEL_ID = "vpn13_xray"
        private const val NOTIFICATION_ID = 1313

        @Volatile var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        @Volatile private var currentState = "disconnected"
        @Volatile private var currentMessage = "آماده اتصال"
        @Volatile private var currentUploadSpeed = 0L
        @Volatile private var currentDownloadSpeed = 0L
        @Volatile private var currentUploadTotal = 0L
        @Volatile private var currentDownloadTotal = 0L
        private val mainHandler = Handler(Looper.getMainLooper())

        fun statusSnapshot(): Map<String, Any> = mapOf(
            "state" to currentState,
            "message" to currentMessage,
            "uploadSpeed" to currentUploadSpeed,
            "downloadSpeed" to currentDownloadSpeed,
            "uploadTotal" to currentUploadTotal,
            "downloadTotal" to currentDownloadTotal
        )

        private fun publishEvent(state: String, message: String) {
            currentState = state
            currentMessage = message
            mainHandler.post { eventSink?.success(statusSnapshot()) }
        }
    }
}
