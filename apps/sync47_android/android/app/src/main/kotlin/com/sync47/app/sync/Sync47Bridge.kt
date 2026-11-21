package com.sync47.app.sync

import android.Manifest
import android.app.StatusBarManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executor
import kotlin.concurrent.thread

class Sync47Bridge(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.sync47.app/bridge"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val clipStore = ClipStore.getInstance(context)

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                SyncSocketService.BROADCAST_STATUS -> {
                    val status = intent.getStringExtra(SyncSocketService.EXTRA_STATUS) ?: "waiting"
                    channel.invokeMethod("onStatusChanged", status)
                }
                SyncSocketService.BROADCAST_CLIP_RECEIVED -> {
                    val map = mapOf(
                        "text" to (intent.getStringExtra("text") ?: ""),
                        "hash" to (intent.getStringExtra("hash") ?: ""),
                        "source" to (intent.getStringExtra("source") ?: "laptop"),
                        "timestamp" to intent.getLongExtra("timestamp", System.currentTimeMillis())
                    )
                    channel.invokeMethod("onClipReceived", map)
                }
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        val filter = IntentFilter().apply {
            addAction(SyncSocketService.BROADCAST_STATUS)
            addAction(SyncSocketService.BROADCAST_CLIP_RECEIVED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "savePairing" -> {
                val id = call.argument<String>("id") ?: ""
                val name = call.argument<String>("name") ?: ""
                val ip = call.argument<String>("ip") ?: ""
                val port = call.argument<Int>("port") ?: 47471
                val key = call.argument<String>("key") ?: ""

                clipStore.savePairing(id, name, ip, port, key)
                SyncSocketService.startService(context)
                result.success(true)
            }
            "getPairingInfo" -> {
                val map = mapOf(
                    "isPaired" to clipStore.isPaired(),
                    "id" to (clipStore.getPcId() ?: ""),
                    "name" to (clipStore.getPcName() ?: ""),
                    "ip" to (clipStore.getPcIp() ?: ""),
                    "port" to clipStore.getPcPort(),
                    "key" to (clipStore.getEncryptionKey() ?: ""),
                    "isPaused" to clipStore.isPaused(),
                    "autoSyncWifi" to clipStore.isAutoSyncWifi(),
                    "autoSendAccessibility" to clipStore.isAutoSendAccessibility()
                )
                result.success(map)
            }
            "getConnectionStatus" -> {
                result.success(SyncSocketService.getStatus())
            }
            "getHistory" -> {
                val clips = clipStore.getClips()
                val list = clips.map {
                    mapOf(
                        "id" to it.id,
                        "text" to it.text,
                        "hash" to it.hash,
                        "source" to it.source,
                        "timestamp" to it.timestamp
                    )
                }
                result.success(list)
            }
            "deleteClip" -> {
                val id = call.argument<String>("id") ?: ""
                clipStore.deleteClip(id)
                result.success(true)
            }
            "clearHistory" -> {
                clipStore.clearClips()
                result.success(true)
            }
            "unpair" -> {
                clipStore.unpair()
                SyncSocketService.startService(context) // restarts/updates status
                result.success(true)
            }
            "togglePause" -> {
                val paused = call.argument<Boolean>("paused") ?: !clipStore.isPaused()
                clipStore.setPaused(paused)
                SyncSocketService.startService(context)
                result.success(paused)
            }
            "setAutoSyncWifi" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                clipStore.setAutoSyncWifi(enabled)
                result.success(true)
            }
            "setAutoSendAccessibility" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                clipStore.setAutoSendAccessibility(enabled)
                result.success(true)
            }
            "sendClip" -> {
                val text = call.argument<String>("text") ?: ""
                if (text.isNotEmpty()) {
                    SyncSocketService.sendText(context, text)
                    result.success(true)
                } else {
                    result.error("EMPTY_TEXT", "Text cannot be empty", null)
                }
            }
            "requestAddTile" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val sbm = context.getSystemService(StatusBarManager::class.java)
                    val component = ComponentName(context, Sync47TileService::class.java)
                    sbm?.requestAddTileService(
                        component,
                        "Sync47",
                        Icon.createWithResource(context, android.R.drawable.stat_notify_sync),
                        Executor { it.run() }
                    ) { _ -> }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "testConnection" -> {
                val ip = call.argument<String>("ip")?.takeIf { it.isNotEmpty() } ?: clipStore.getPcIp() ?: ""
                val port = call.argument<Int>("port") ?: clipStore.getPcPort()
                if (ip.isEmpty()) {
                    result.success(mapOf("success" to false, "message" to "No IP address configured"))
                    return
                }
                thread {
                    val (success, message) = SyncSocketService.testConnection(ip, port)
                    Handler(Looper.getMainLooper()).post {
                        result.success(mapOf("success" to success, "message" to message))
                    }
                }
            }
            "checkPermissions" -> {
                val accessibilityEnabled = isAccessibilityServiceEnabled(context, Sync47AccessibilityService::class.java)
                val overlayGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Settings.canDrawOverlays(context)
                } else {
                    true
                }
                val readLogsGranted = context.checkCallingOrSelfPermission(Manifest.permission.READ_LOGS) == PackageManager.PERMISSION_GRANTED
                result.success(
                    mapOf(
                        "accessibilityEnabled" to accessibilityEnabled,
                        "overlayGranted" to overlayGranted,
                        "readLogsGranted" to readLogsGranted
                    )
                )
            }
            "openAccessibilitySettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERR_OPEN_ACCESSIBILITY", e.message, null)
                }
            }
            "openOverlaySettings" -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                } catch (e: Exception) {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", context.packageName, null)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("ERR_OPEN_OVERLAY", e2.message, null)
                    }
                }
            }
            "manualPair" -> {
                val ip = call.argument<String>("ip")?.trim() ?: ""
                val port = call.argument<Int>("port") ?: 47471
                val name = call.argument<String>("name") ?: "PC Workstation"
                val key = call.argument<String>("key") ?: clipStore.getEncryptionKey() ?: ""
                val id = call.argument<String>("id") ?: clipStore.getPcId() ?: UUID.randomUUID().toString()

                if (ip.isEmpty()) {
                    result.error("INVALID_IP", "IP address cannot be empty", null)
                    return
                }

                clipStore.savePairing(id, name, ip, port, key)
                SyncSocketService.startService(context)
                result.success(true)
            }
            "openBatterySettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", context.packageName, null)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(appSettings)
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun isAccessibilityServiceEnabled(context: Context, serviceClass: Class<*>): Boolean {
        val expectedComponentName = ComponentName(context, serviceClass).flattenToString()
        val shortComponentName = ComponentName(context, serviceClass).flattenToShortString()
        val enabledServicesSetting = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)
        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            if (componentNameString.equals(expectedComponentName, ignoreCase = true) ||
                componentNameString.equals(shortComponentName, ignoreCase = true) ||
                (componentNameString.contains(context.packageName) && componentNameString.contains(serviceClass.simpleName))) {
                return true
            }
        }
        return false
    }

    fun dispose() {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
    }
}
