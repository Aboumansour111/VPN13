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
    @Volatile private var uiForeground = true

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UI_FOREGROUND, ACTION_UI_BACKGROUND -> {
                updateUiVisibility(intent.action == ACTION_UI_FOREGROUND)
                return START_NOT_STICKY
            }
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
                val dnsAddress = intent.getStringExtra(EXTRA_DNS)?.takeIf { it.isNotBlank() } ?: "1.1.1.1"
                val excludedApps = intent.getStringArrayListExtra(EXTRA_EXCLUDED_APPS) ?: arrayListOf()
                worker.execute { startTunnel(config, dnsAddress, excludedApps) }
                return START_NOT_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun startTunnel(config: String, dnsAddress: String, excludedApps: List<String>) {
        try {
            stopCoreAndTunnel()
            publish("connecting", "در حال راه‌اندازی هسته Xray")
            val builder = Builder()
                .setSession(profileName)
                .setMtu(1500)
                .addAddress("10.13.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer(dnsAddress)
                .addAddress("fd13:13::1", 126)
                .addRoute("::", 0)
                .addDisallowedApplication(packageName)
            excludedApps.filter { it.isNotBlank() && it != packageName }.forEach { app ->
                try { builder.addDisallowedApplication(app) } catch (_: Exception) { /* app may have been uninstalled */ }
            }

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
        instance = null
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
        val notificationText = listOf(
            "حجم مصرفی این اتصال",
            "دریافت: ${formatDataSize(currentDownloadTotal)}",
            "ارسال: ${formatDataSize(currentUploadTotal)}",
            "سرعت لحظه‌ای",
            "دریافت: ${formatSpeed(currentDownloadSpeed)}",
            "ارسال: ${formatSpeed(currentUploadSpeed)}"
        ).joinToString("\\n")
        return builder
            .setContentTitle(profileName)
            .setContentText(notificationText)
            .setStyle(Notification.BigTextStyle().bigText(notificationText).setBigContentTitle(profileName))
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

    private fun startStatsPolling(core: CoreController, resetCounters: Boolean = true) {
        stopStatsPolling()
        if (resetCounters) {
            currentUploadSpeed = 0L
            currentDownloadSpeed = 0L
            currentUploadTotal = 0L
            currentDownloadTotal = 0L
            lastUploadSample = 0L
            lastDownloadSample = 0L
        }
        lastStatsSampleNanos = System.nanoTime()
        // Refresh once per second so notification speeds reflect live traffic.
        val intervalSeconds = 1L
        statsTask = statsWorker.scheduleWithFixedDelay({
            if (controller !== core || !core.isRunning) return@scheduleWithFixedDelay
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
                // QueryAllOutboundTrafficStats atomically READS AND RESETS counters.
                // Values returned here are bytes since the previous poll, not lifetime totals.
                val nowNanos = System.nanoTime()
                val elapsedSeconds = ((nowNanos - lastStatsSampleNanos).coerceAtLeast(1L)) / 1_000_000_000.0
                currentUploadSpeed = (uploaded / elapsedSeconds).toLong()
                currentDownloadSpeed = (downloaded / elapsedSeconds).toLong()
                lastStatsSampleNanos = nowNanos
                currentUploadTotal += uploaded
                currentDownloadTotal += downloaded
                publishEvent(currentState, currentMessage)
                updateNotification()
            } catch (_: Exception) {
                // Stats polling must not interrupt an active VPN session.
            }
        }, intervalSeconds, intervalSeconds, TimeUnit.SECONDS)
    }

    private fun localizedNumber(value: Double, fractionDigits: Int): String {
        return java.text.NumberFormat.getNumberInstance(java.util.Locale("fa")).apply {
            minimumFractionDigits = fractionDigits
            maximumFractionDigits = fractionDigits
        }.format(value)
    }

    private fun formatSpeed(bytesPerSecond: Long): String {
        val speed = bytesPerSecond.coerceAtLeast(0L).toDouble()
        return when {
            speed >= 1_073_741_824.0 -> "${localizedNumber(speed / 1_073_741_824.0, 2)} گیگابایت بر ثانیه"
            speed >= 1_048_576.0 -> "${localizedNumber(speed / 1_048_576.0, 2)} مگابایت بر ثانیه"
            speed >= 1_024.0 -> "${localizedNumber(speed / 1_024.0, 1)} کیلوبایت بر ثانیه"
            else -> "${localizedNumber(speed, 0)} بایت بر ثانیه"
        }
    }

    private fun formatDataSize(bytes: Long): String {
        val size = bytes.coerceAtLeast(0L).toDouble()
        return when {
            size >= 1_073_741_824.0 -> "${localizedNumber(size / 1_073_741_824.0, 2)} گیگابایت"
            size >= 1_048_576.0 -> "${localizedNumber(size / 1_048_576.0, 2)} مگابایت"
            size >= 1_024.0 -> "${localizedNumber(size / 1_024.0, 1)} کیلوبایت"
            else -> "${localizedNumber(size, 0)} بایت"
        }
    }

    private fun updateNotification() {
        if (currentState != "connected") return
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    private fun updateUiVisibility(foreground: Boolean) {
        if (uiForeground == foreground) return
        uiForeground = foreground
        controller?.takeIf { it.isRunning }?.let { startStatsPolling(it, resetCounters = false) }
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
        const val ACTION_UI_FOREGROUND = "com.vpn13.vpn13_client.action.UI_FOREGROUND"
        const val ACTION_UI_BACKGROUND = "com.vpn13.vpn13_client.action.UI_BACKGROUND"
        @Volatile private var instance: XrayVpnService? = null

        fun updateAppVisibility(foreground: Boolean) {
            instance?.updateUiVisibility(foreground)
        }
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_PROFILE_NAME = "profile_name"
        const val EXTRA_DNS = "dns_address"
        const val EXTRA_EXCLUDED_APPS = "excluded_apps"
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
