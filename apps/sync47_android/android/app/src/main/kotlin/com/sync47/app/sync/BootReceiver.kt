package com.sync47.app.sync

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            val store = ClipStore.getInstance(context)
            if (store.isPaired() && store.isAutoSyncWifi()) {
                SyncSocketService.startService(context)
            }
        }
    }
}
