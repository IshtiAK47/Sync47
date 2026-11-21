package com.sync47.app.sync

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.sync47.app.R

class Sync47TileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val store = ClipStore.getInstance(this)

        if (store.isPaired() && !store.isPaused()) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "Sync47"
            tile.subtitle = "Tap to Send Clip"
        } else if (store.isPaused()) {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "Sync47 (Paused)"
            tile.subtitle = "Paused"
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "Sync47"
            tile.subtitle = "Unpaired"
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()

        val intent = Intent(this, ClipboardCaptureActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
