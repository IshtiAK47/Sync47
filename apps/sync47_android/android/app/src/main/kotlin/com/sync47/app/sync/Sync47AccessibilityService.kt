package com.sync47.app.sync

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Primary Engine — Accessibility Service + Invisible 1×1 Overlay.
 * Listens for copy-related events in any app and triggers an invisible 1×1 focusable overlay
 * to read ClipboardManager and push the clip to the PC clipboard with ZERO manual taps.
 */
class Sync47AccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "Sync47Accessibility"
        @Volatile
        var isRunning: Boolean = false
    }

    private lateinit var clipStore: ClipStore
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastDebounceTime = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        clipStore = ClipStore.getInstance(this)
        isRunning = true
        Log.d(TAG, "Sync47 Accessibility Service connected.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !clipStore.isPaired() || clipStore.isPaused()) {
            return
        }

        val eventType = event.eventType
        val isCopyCandidate = eventType == AccessibilityEvent.TYPE_VIEW_CLICKED ||
                eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED ||
                eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED ||
                eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED

        if (!isCopyCandidate) return

        val now = System.currentTimeMillis()
        if (now - lastDebounceTime < 250) {
            return
        }
        lastDebounceTime = now

        // Check if event text or class implies a copy or selection action
        val textList = event.text
        val className = event.className?.toString() ?: ""

        // Debounce slightly to allow the OS clipboard to complete writing
        mainHandler.postDelayed({
            ClipboardOverlayHelper.captureClipboard(this, isAccessibilityContext = true) { text ->
                Log.d(TAG, "Captured clipboard from accessibility trigger: ${text.take(20)}...")
                SyncSocketService.sendText(this, text)
            }
        }, 150)
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility Service interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
    }
}
