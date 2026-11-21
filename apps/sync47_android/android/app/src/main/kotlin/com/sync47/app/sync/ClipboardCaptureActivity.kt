package com.sync47.app.sync

import android.app.Activity
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * Transparent, zero-animation trampoline Activity.
 * Gains brief window focus (~50ms) to read ClipboardManager (Android 10+ compliant),
 * pushes the payload directly to the paired PC, shows a brief toast, and finishes immediately.
 */
class ClipboardCaptureActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Set window to 1x1 transparent to avoid any visual flicker
        window.setLayout(1, 1)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            handleClipboardCapture()
        }
    }

    private fun handleClipboardCapture() {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val primaryClip = clipboard.primaryClip

            if (primaryClip == null || primaryClip.itemCount == 0) {
                Toast.makeText(this, "Clipboard is empty", Toast.LENGTH_SHORT).show()
                finish()
                return
            }

            // Sensitive content check (Android 13+ Bitwarden/1Password/Keepass flag)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val extras = primaryClip.description.extras
                if (extras != null && extras.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false)) {
                    Toast.makeText(this, "Ignored sensitive password", Toast.LENGTH_SHORT).show()
                    finish()
                    return
                }
            }

            val text = primaryClip.getItemAt(0)?.coerceToText(this)?.toString()
            if (!text.isNullOrEmpty()) {
                val store = ClipStore.getInstance(this)
                if (!store.isPaired()) {
                    Toast.makeText(this, "PC not paired yet. Open Sync47 to pair.", Toast.LENGTH_SHORT).show()
                } else {
                    SyncSocketService.sendText(this, text)
                    Toast.makeText(this, "Sent to PC ✓", Toast.LENGTH_SHORT).show()
                }
            } else {
                Toast.makeText(this, "No text in clipboard", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Error reading clipboard: ${e.message}", Toast.LENGTH_SHORT).show()
        } finally {
            finish()
        }
    }
}
