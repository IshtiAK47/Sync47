package com.sync47.app.sync

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager

/**
 * Invisible 1x1 pixel focusable overlay reader.
 * Bypasses Android 10+ background clipboard read restriction by briefly (~80ms)
 * acquiring window focus without visual disruption to the user.
 */
object ClipboardOverlayHelper {
    private const val TAG = "ClipboardOverlayHelper"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeView: View? = null

    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Attempts an invisible clipboard read using a 1x1 transparent focusable overlay.
     * @param context Application context or AccessibilityService context
     * @param isAccessibilityContext If true, uses TYPE_ACCESSIBILITY_OVERLAY (no SYSTEM_ALERT_WINDOW needed)
     */
    fun captureClipboard(
        context: Context,
        isAccessibilityContext: Boolean = false,
        onCaptured: (String) -> Unit
    ) {
        mainHandler.post {
            try {
                if (!isAccessibilityContext && !canDrawOverlays(context)) {
                    Log.d(TAG, "Cannot capture: overlay permission not granted.")
                    return@post
                }

                val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                    ?: return@post
                val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                    ?: return@post

                // Clean up previous view if any
                removeExistingOverlay(windowManager)

                val windowType = if (isAccessibilityContext) {
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    1,
                    1,
                    windowType,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.START or Gravity.TOP
                    x = 0
                    y = 0
                }

                var processed = false

                val overlayView = object : View(context) {
                    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                        super.onWindowFocusChanged(hasWindowFocus)
                        if (hasWindowFocus && !processed) {
                            processed = true
                            try {
                                readAndEmitClipboard(context, clipboardManager, onCaptured)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error in readAndEmitClipboard: $e")
                            } finally {
                                removeSelf()
                            }
                        }
                    }

                    fun removeSelf() {
                        mainHandler.post {
                            try {
                                if (activeView == this) {
                                    windowManager.removeView(this)
                                    activeView = null
                                }
                            } catch (_: Exception) {}
                        }
                    }
                }

                overlayView.isFocusable = true
                overlayView.isFocusableInTouchMode = true

                activeView = overlayView
                windowManager.addView(overlayView, params)
                overlayView.requestFocus()

                // Safety timeout: automatically dismiss after 100ms
                mainHandler.postDelayed({
                    overlayView.removeSelf()
                }, 100)

            } catch (e: Exception) {
                Log.e(TAG, "Error creating invisible overlay: $e")
            }
        }
    }

    private fun readAndEmitClipboard(
        context: Context,
        clipboardManager: ClipboardManager,
        onCaptured: (String) -> Unit
    ) {
        val primaryClip = clipboardManager.primaryClip ?: return
        if (primaryClip.itemCount == 0) return

        // Skip sensitive clips (e.g. password managers on Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val extras = primaryClip.description.extras
            if (extras != null && extras.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false)) {
                Log.d(TAG, "Ignored sensitive password clip.")
                return
            }
        }

        val text = primaryClip.getItemAt(0)?.coerceToText(context)?.toString()
        if (!text.isNullOrEmpty()) {
            val store = ClipStore.getInstance(context)
            val hash = CryptoHelper.sha256Hex(text)
            if (store.shouldSync(hash)) {
                Log.d(TAG, "Clipboard captured via 1x1 overlay: ${text.take(20)}...")
                onCaptured(text)
            }
        }
    }

    private fun removeExistingOverlay(windowManager: WindowManager) {
        try {
            activeView?.let {
                windowManager.removeView(it)
                activeView = null
            }
        } catch (_: Exception) {}
    }
}
