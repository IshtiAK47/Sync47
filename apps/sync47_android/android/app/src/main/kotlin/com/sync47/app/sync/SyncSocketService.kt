package com.sync47.app.sync

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ConnectException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class SyncSocketService : Service() {
    companion object {
        private const val TAG = "SyncSocketService"
        const val ACTION_START = "com.sync47.app.START_SYNC"
        const val ACTION_STOP = "com.sync47.app.STOP_SYNC"
        const val ACTION_SEND_TEXT = "com.sync47.app.SEND_TEXT"
        const val EXTRA_TEXT = "extra_text"

        const val BROADCAST_STATUS = "com.sync47.app.STATUS_CHANGED"
        const val BROADCAST_CLIP_RECEIVED = "com.sync47.app.CLIP_RECEIVED"
        const val EXTRA_STATUS = "status"

        private const val NOTIFICATION_CHANNEL_SERVICE = "sync47_service_channel"
        private const val NOTIFICATION_CHANNEL_CLIPS = "sync47_clips_channel"
        private const val NOTIFICATION_ID_SERVICE = 1047
        private const val NOTIFICATION_ID_CLIP_BASE = 2000

        @Volatile
        private var currentStatus: String = "Waiting for Wi-Fi"

        fun getStatus(): String = currentStatus

        fun startService(context: Context) {
            val intent = Intent(context, SyncSocketService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting service: $e")
            }
        }

        fun sendText(context: Context, text: String) {
            val intent = Intent(context, SyncSocketService::class.java).apply {
                action = ACTION_SEND_TEXT
                putExtra(EXTRA_TEXT, text)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error sending text to service: $e")
            }
        }

        fun testConnection(ip: String, port: Int): Pair<Boolean, String> {
            val start = System.currentTimeMillis()
            return try {
                val request = Request.Builder().url("http://$ip:$port/health").build()
                val client = OkHttpClient.Builder()
                    .connectTimeout(3, TimeUnit.SECONDS)
                    .readTimeout(3, TimeUnit.SECONDS)
                    .build()
                val response = client.newCall(request).execute()
                val latency = System.currentTimeMillis() - start
                if (response.isSuccessful) {
                    Pair(true, "Reachable in ${latency}ms (200 OK)")
                } else {
                    Pair(false, "Server returned HTTP ${response.code}")
                }
            } catch (e: SocketTimeoutException) {
                Pair(false, "Timeout reaching $ip:$port — check Windows Firewall")
            } catch (e: ConnectException) {
                Pair(false, "Connection refused at $ip:$port — is Sync47 running on PC?")
            } catch (e: Exception) {
                Pair(false, "${e.javaClass.simpleName}: ${e.message ?: "Failed"}")
            }
        }
    }

    private lateinit var clipStore: ClipStore
    private lateinit var clipboardManager: ClipboardManager
    private lateinit var connectivityManager: ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var okHttpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var isWifiConnected = false
    private var isRunning = false
    private var udpBeaconThread: Thread? = null
    private var udpSocket: DatagramSocket? = null
    private var logcatThread: Thread? = null
    private var reconnectDelaySeconds = 1L

    private val clipChangedListener = ClipboardManager.OnPrimaryClipChangedListener {
        // Triggered when clipboard changes
        if (clipStore.isPaired() && !clipStore.isPaused()) {
            ClipboardOverlayHelper.captureClipboard(this, false) { text ->
                performSend(text)
            }
        }
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.d(TAG, "Wi-Fi network detected.")
            isWifiConnected = true
            mainHandler.post {
                reconnectDelaySeconds = 1L
                connectWebSocket()
            }
            startUdpBeaconListener()
        }

        override fun onLost(network: Network) {
            Log.d(TAG, "Wi-Fi network lost.")
            isWifiConnected = false
            mainHandler.post { disconnectWebSocket("Wi-Fi Disconnected") }
            stopUdpBeaconListener()
        }
    }

    override fun onCreate() {
        super.onCreate()
        clipStore = ClipStore.getInstance(this)
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        createNotificationChannels()
        registerWifiCallback()

        try {
            clipboardManager.addPrimaryClipChangedListener(clipChangedListener)
        } catch (e: Exception) {
            Log.e(TAG, "Error registering clip listener: $e")
        }

        startLogcatWatcherIfPermitted()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID_SERVICE, buildForegroundNotification("Sync47 Active"))

        when (intent?.action) {
            ACTION_START -> {
                isRunning = true
                if (isWifiConnected) {
                    connectWebSocket()
                } else {
                    // Check if current active network has Wi-Fi
                    val activeNet = connectivityManager.activeNetwork
                    val caps = connectivityManager.getNetworkCapabilities(activeNet)
                    if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
                        isWifiConnected = true
                        connectWebSocket()
                    } else {
                        updateStatus("Waiting for Wi-Fi")
                    }
                }
                startLogcatWatcherIfPermitted()
            }
            ACTION_STOP -> {
                isRunning = false
                disconnectWebSocket("Service stopped")
                stopSelf()
            }
            ACTION_SEND_TEXT -> {
                val text = intent.getStringExtra(EXTRA_TEXT)
                if (!text.isNullOrEmpty()) {
                    performSend(text)
                }
            }
        }

        return START_STICKY
    }

    private fun registerWifiCallback() {
        try {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            connectivityManager.registerNetworkCallback(request, networkCallback)

            val currentNetwork = connectivityManager.activeNetwork
            val caps = connectivityManager.getNetworkCapabilities(currentNetwork)
            isWifiConnected = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } catch (e: Exception) {
            Log.e(TAG, "Error registering network callback: $e")
            isWifiConnected = true // Fallback so we don't get stuck
        }
    }

    @Synchronized
    fun connectWebSocket() {
        if (!clipStore.isPaired()) {
            updateStatus("Waiting for PC Pairing")
            return
        }

        if (clipStore.isPaused()) {
            updateStatus("Sync Paused")
            return
        }

        if (webSocket != null) return

        val ip = clipStore.getPcIp() ?: return
        val port = clipStore.getPcPort()
        val pcName = clipStore.getPcName() ?: "PC"
        val url = "ws://$ip:$port/ws"

        Log.d(TAG, "Connecting WebSocket to $url")
        updateStatus("Connecting to $pcName ($ip:$port)...")

        if (okHttpClient == null) {
            okHttpClient = OkHttpClient.Builder()
                .pingInterval(20, TimeUnit.SECONDS) // Ping/pong every 20s
                .connectTimeout(4, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
        }

        val request = Request.Builder().url(url).build()
        webSocket = okHttpClient?.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WebSocket connected to $pcName")
                reconnectDelaySeconds = 1L
                updateStatus("Connected to $pcName ($ip)")
                sendHello(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleIncomingMessage(webSocket, text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "WebSocket closing: $code / $reason")
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "WebSocket closed: $reason")
                this@SyncSocketService.webSocket = null
                if (isRunning && !clipStore.isPaused()) {
                    updateStatus("Reconnecting to $pcName ($ip)...")
                    scheduleReconnect()
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket failure: ${t.javaClass.simpleName}: ${t.message}")
                this@SyncSocketService.webSocket = null

                val errorMsg = when (t) {
                    is SocketTimeoutException -> "Timeout reaching $ip:$port — check Windows Firewall"
                    is ConnectException -> "Connection refused at $ip:$port — is PC app running?"
                    else -> "Reconnecting to $ip:$port (${t.message ?: "Lost connection"})"
                }
                updateStatus(errorMsg)
                scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        if (!clipStore.isPaired() || clipStore.isPaused()) return

        val delay = reconnectDelaySeconds
        reconnectDelaySeconds = (reconnectDelaySeconds * 2).coerceAtMost(5L) // Exponential backoff (1s, 2s, 4s, 5s max)

        mainHandler.postDelayed({
            if (webSocket == null && !clipStore.isPaused()) {
                connectWebSocket()
            }
        }, delay * 1000)
    }

    @Synchronized
    private fun disconnectWebSocket(reason: String) {
        webSocket?.close(1000, reason)
        webSocket = null
        updateStatus(reason)
    }

    private fun sendHello(ws: WebSocket) {
        val deviceId = Build.FINGERPRINT.hashCode().toString()
        val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
        val helloJson = JSONObject().apply {
            put("type", "hello")
            put("device_id", deviceId)
            put("device_name", deviceName)
            put("timestamp", System.currentTimeMillis())
            put("content_type", "text/plain")
            put("hash", "")
            put("payload", "")
        }
        ws.send(helloJson.toString())
    }

    private fun handleIncomingMessage(ws: WebSocket, message: String) {
        try {
            val json = JSONObject(message)
            val type = json.optString("type", "clip")

            if (type == "clip") {
                val hash = json.optString("hash", "")
                val payload = json.optString("payload", "")
                val timestamp = json.optLong("timestamp", System.currentTimeMillis())

                // 3-second echo-loop prevention
                if (!clipStore.shouldSync(hash)) {
                    Log.d(TAG, "Duplicate clip hash dropped: $hash")
                    return
                }

                val key = clipStore.getEncryptionKey() ?: return
                val decrypted = CryptoHelper.decrypt(payload, key)

                // Record hash so local watcher won't bounce it back
                clipStore.recordHash(hash)

                // Save to SQLite
                clipStore.saveClip(decrypted, hash, "laptop", timestamp)

                // Write to Android Clipboard directly
                mainHandler.post {
                    try {
                        val clip = ClipData.newPlainText("Sync47", decrypted)
                        clipboardManager.setPrimaryClip(clip)
                        Log.d(TAG, "Copied remote clip to Android clipboard.")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error writing to ClipboardManager: $e")
                    }
                }

                // If URL, show 1-tap notification
                if (decrypted.trim().startsWith("http://") || decrypted.trim().startsWith("https://")) {
                    showUrlNotification(decrypted.trim())
                }

                // Broadcast to Flutter UI
                val intent = Intent(BROADCAST_CLIP_RECEIVED).apply {
                    putExtra("text", decrypted)
                    putExtra("hash", hash)
                    putExtra("source", "laptop")
                    putExtra("timestamp", timestamp)
                    setPackage(packageName)
                }
                sendBroadcast(intent)

                // Send ack
                val ack = JSONObject().apply {
                    put("type", "ack")
                    put("device_id", Build.FINGERPRINT.hashCode().toString())
                    put("device_name", "${Build.MANUFACTURER} ${Build.MODEL}")
                    put("timestamp", System.currentTimeMillis())
                    put("hash", hash)
                    put("payload", "")
                }
                ws.send(ack.toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling incoming message: $e")
        }
    }

    fun performSend(text: String) {
        if (!clipStore.isPaired() || clipStore.isPaused()) return
        val key = clipStore.getEncryptionKey() ?: return

        thread {
            try {
                val hash = CryptoHelper.sha256Hex(text)
                if (!clipStore.shouldSync(hash)) {
                    Log.d(TAG, "Dropping duplicate outgoing clip: $hash")
                    return@thread
                }

                val encryptedPayload = CryptoHelper.encrypt(text, key)
                val packet = JSONObject().apply {
                    put("type", "clip")
                    put("device_id", Build.FINGERPRINT.hashCode().toString())
                    put("device_name", "${Build.MANUFACTURER} ${Build.MODEL}")
                    put("timestamp", System.currentTimeMillis())
                    put("content_type", "text/plain")
                    put("hash", hash)
                    put("payload", encryptedPayload)
                }

                // Save to local SQLite
                clipStore.saveClip(text, hash, "phone", System.currentTimeMillis())

                val ws = webSocket
                if (ws != null) {
                    ws.send(packet.toString())
                    Log.d(TAG, "Sent clip via active WebSocket to PC.")
                } else {
                    // Try one-shot connection to PC if socket is reconnecting
                    val ip = clipStore.getPcIp() ?: return@thread
                    val port = clipStore.getPcPort()
                    val request = Request.Builder().url("ws://$ip:$port/ws").build()
                    val client = OkHttpClient.Builder().connectTimeout(3, TimeUnit.SECONDS).build()
                    client.newWebSocket(request, object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            sendHello(webSocket)
                            webSocket.send(packet.toString())
                            mainHandler.postDelayed({ webSocket.close(1000, "Done") }, 500)
                        }
                    })
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error sending text to PC: $e")
            }
        }
    }

    // --- KDE Connect Style READ_LOGS Watcher ---
    private fun startLogcatWatcherIfPermitted() {
        if (logcatThread != null) return

        val hasReadLogs = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_LOGS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasReadLogs) {
            Log.d(TAG, "READ_LOGS permission not granted yet.")
            return
        }

        logcatThread = thread(name = "Sync47LogcatWatcher") {
            Log.d(TAG, "Starting READ_LOGS logcat watcher thread...")
            try {
                // Clear existing logcat buffer
                Runtime.getRuntime().exec("logcat -c").waitFor()

                val process = Runtime.getRuntime().exec("logcat -v brief ClipboardService:E *:S")
                val reader = BufferedReader(InputStreamReader(process.inputStream))

                while (isRunning) {
                    val currentLine = reader.readLine() ?: break
                    // Watch for Android denying clipboard access to our background app
                    if (currentLine.contains("Denying clipboard access to com.sync47.app") ||
                        currentLine.contains("ClipboardService")
                    ) {
                        Log.d(TAG, "Detected background clipboard denial event. Triggering 1x1 overlay capture...")
                        ClipboardOverlayHelper.captureClipboard(this, false) { text ->
                            performSend(text)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Logcat watcher ended: ${e.message}")
            }
        }
    }

    private fun startUdpBeaconListener() {
        if (udpBeaconThread != null) return
        udpBeaconThread = thread(name = "Sync47UdpBeaconListener") {
            try {
                udpSocket = DatagramSocket(47470, InetAddress.getByName("0.0.0.0")).apply {
                    broadcast = true
                    soTimeout = 0
                }
                val buffer = ByteArray(1024)
                while (isWifiConnected && udpSocket != null && !udpSocket!!.isClosed) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    udpSocket?.receive(packet)
                    val jsonStr = String(packet.data, 0, packet.length, Charsets.UTF_8)
                    try {
                        val json = JSONObject(jsonStr)
                        if (json.optString("app") == "sync47") {
                            val beaconPort = json.optInt("port", 47471)
                            val beaconIp = packet.address.hostAddress
                            if (beaconIp != null && beaconIp != clipStore.getPcIp()) {
                                Log.d(TAG, "Discovered PC IP via UDP beacon: $beaconIp:$beaconPort")
                                clipStore.updatePcIp(beaconIp)
                                if (webSocket == null) {
                                    mainHandler.post { connectWebSocket() }
                                }
                            }
                        }
                    } catch (_: Exception) {}
                }
            } catch (e: Exception) {
                Log.d(TAG, "UDP listener exited: ${e.message}")
            }
        }
    }

    private fun stopUdpBeaconListener() {
        try {
            udpSocket?.close()
            udpSocket = null
            udpBeaconThread?.interrupt()
            udpBeaconThread = null
        } catch (_: Exception) {}
    }

    private fun updateStatus(status: String) {
        currentStatus = status
        val intent = Intent(BROADCAST_STATUS).apply {
            putExtra(EXTRA_STATUS, status)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    private fun showUrlNotification(url: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            url.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_CLIPS)
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setContentTitle("Link received from PC")
            .setContentText(url)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_menu_view, "Open Link", pendingIntent)
            .setContentIntent(pendingIntent)
            .build()

        val notifId = NOTIFICATION_ID_CLIP_BASE + (System.currentTimeMillis() % 1000).toInt()
        notificationManager.notify(notifId, notification)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            val serviceChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_SERVICE,
                "Sync47 Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows live connection status to your PC"
                setShowBadge(false)
            }

            val clipsChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_CLIPS,
                "Sync47 URL Clips",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Dismissible notifications for received web links"
            }

            manager?.createNotificationChannel(serviceChannel)
            manager?.createNotificationChannel(clipsChannel)
        }
    }

    private fun buildForegroundNotification(title: String): Notification {
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_SERVICE)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText("Local Wi-Fi clipboard sync active")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        try {
            clipboardManager.removePrimaryClipChangedListener(clipChangedListener)
        } catch (_: Exception) {}
        logcatThread?.interrupt()
        logcatThread = null
        stopUdpBeaconListener()
        disconnectWebSocket("Service destroyed")
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        } catch (_: Exception) {}
    }
}
