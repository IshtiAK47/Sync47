package com.sync47.app.sync

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Handles Android Share Sheet ACTION_SEND (text/plain) intent.
 * Select text anywhere -> Share -> Sync47 pushes straight to PC without opening Flutter UI.
 */
class ShareToPcActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setLayout(1, 1)

        val intent = intent
        if (Intent.ACTION_SEND == intent.action && "text/plain" == intent.type) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!sharedText.isNullOrEmpty()) {
                val store = ClipStore.getInstance(this)
                if (!store.isPaired()) {
                    Toast.makeText(this, "PC not paired yet. Open Sync47 to pair.", Toast.LENGTH_SHORT).show()
                } else {
                    SyncSocketService.sendText(this, sharedText)
                    Toast.makeText(this, "Shared to PC ✓", Toast.LENGTH_SHORT).show()
                }
            }
        }
        finish()
    }
}
