package com.sync47.app.sync

import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.UUID

data class ClipRecord(
    val id: String,
    val text: String,
    val hash: String,
    val source: String, // "phone" or "laptop"
    val timestamp: Long
) {
    val isUrl: Boolean
        get() {
            val t = text.trim()
            return t.startsWith("http://") || t.startsWith("https://")
        }
}

class ClipStore(private val context: Context) {
    companion object {
        private const val PREFS_FILE = "sync47_secure_prefs"
        private const val KEY_PC_ID = "pc_id"
        private const val KEY_PC_NAME = "pc_name"
        private const val KEY_PC_IP = "pc_ip"
        private const val KEY_PC_PORT = "pc_port"
        private const val KEY_ENCRYPTION_KEY = "encryption_key"
        private const val KEY_PAUSED = "is_paused"
        private const val KEY_AUTO_SYNC_WIFI = "auto_sync_wifi"
        private const val KEY_AUTO_SEND_ACCESSIBILITY = "auto_send_accessibility"

        @Volatile
        private var instance: ClipStore? = null

        fun getInstance(context: Context): ClipStore {
            return instance ?: synchronized(this) {
                instance ?: ClipStore(context.applicationContext).also { instance = it }
            }
        }
    }

    private val dbHelper = ClipDbHelper(context)
    private val prefs: SharedPreferences by lazy { initPrefs() }

    // Deduplication state
    @Volatile
    private var lastSyncedHash: String? = null
    private val recentHashes = ArrayDeque<Pair<String, Long>>()
    private val lock = Any()

    private fun initPrefs(): SharedPreferences {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            EncryptedSharedPreferences.create(
                context,
                PREFS_FILE,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (_: Exception) {
            // Fallback for emulators or testing
            context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        }
    }

    // --- Pairing Configuration ---
    fun savePairing(id: String, name: String, ip: String, port: Int, key: String) {
        prefs.edit()
            .putString(KEY_PC_ID, id)
            .putString(KEY_PC_NAME, name)
            .putString(KEY_PC_IP, ip)
            .putInt(KEY_PC_PORT, port)
            .putString(KEY_ENCRYPTION_KEY, key)
            .apply()
    }

    fun updatePcIp(newIp: String) {
        prefs.edit().putString(KEY_PC_IP, newIp).apply()
    }

    fun updatePcEndpoint(ip: String, port: Int) {
        prefs.edit()
            .putString(KEY_PC_IP, ip)
            .putInt(KEY_PC_PORT, port)
            .apply()
    }

    fun getPcId(): String? = prefs.getString(KEY_PC_ID, null)
    fun getPcName(): String? = prefs.getString(KEY_PC_NAME, "PC Workstation")
    fun getPcIp(): String? = prefs.getString(KEY_PC_IP, null)
    fun getPcPort(): Int = prefs.getInt(KEY_PC_PORT, 47471)
    fun getEncryptionKey(): String? = prefs.getString(KEY_ENCRYPTION_KEY, null)
    fun isPaired(): Boolean = !getPcIp().isNullOrEmpty() && !getEncryptionKey().isNullOrEmpty()

    fun unpair() {
        prefs.edit()
            .remove(KEY_PC_ID)
            .remove(KEY_PC_NAME)
            .remove(KEY_PC_IP)
            .remove(KEY_PC_PORT)
            .remove(KEY_ENCRYPTION_KEY)
            .apply()
    }

    fun isPaused(): Boolean = prefs.getBoolean(KEY_PAUSED, false)
    fun setPaused(paused: Boolean) {
        prefs.edit().putBoolean(KEY_PAUSED, paused).apply()
    }

    fun isAutoSyncWifi(): Boolean = prefs.getBoolean(KEY_AUTO_SYNC_WIFI, true)
    fun setAutoSyncWifi(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO_SYNC_WIFI, enabled).apply()
    }

    fun isAutoSendAccessibility(): Boolean = prefs.getBoolean(KEY_AUTO_SEND_ACCESSIBILITY, false)
    fun setAutoSendAccessibility(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO_SEND_ACCESSIBILITY, enabled).apply()
    }

    // --- Echo-Loop Deduplication ---
    fun shouldSync(hash: String): Boolean {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            // Prune entries older than 5 seconds
            while (recentHashes.isNotEmpty() && now - recentHashes.first().second > 5000) {
                recentHashes.removeFirst()
            }

            if (lastSyncedHash == hash) {
                return false
            }

            for (item in recentHashes) {
                if (item.first == hash) {
                    return false
                }
            }

            recordHash(hash)
            return true
        }
    }

    fun recordHash(hash: String) {
        synchronized(lock) {
            lastSyncedHash = hash
            recentHashes.addLast(Pair(hash, System.currentTimeMillis()))
            while (recentHashes.size > 15) {
                recentHashes.removeFirst()
            }
        }
    }

    // --- SQLite History Store ---
    fun saveClip(text: String, hash: String, source: String, timestamp: Long): ClipRecord {
        val id = UUID.randomUUID().toString()
        val record = ClipRecord(id, text, hash, source, timestamp)

        val db = dbHelper.writableDatabase
        db.beginTransaction()
        try {
            // Delete if identical hash exists to move to top
            db.delete(ClipDbHelper.TABLE_CLIPS, "${ClipDbHelper.COL_HASH} = ?", arrayOf(hash))

            val values = ContentValues().apply {
                put(ClipDbHelper.COL_ID, id)
                put(ClipDbHelper.COL_TEXT, text)
                put(ClipDbHelper.COL_HASH, hash)
                put(ClipDbHelper.COL_SOURCE, source)
                put(ClipDbHelper.COL_TIMESTAMP, timestamp)
            }
            db.insertWithOnConflict(
                ClipDbHelper.TABLE_CLIPS,
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE
            )

            // Cap at 20 clips
            db.execSQL(
                "DELETE FROM ${ClipDbHelper.TABLE_CLIPS} WHERE ${ClipDbHelper.COL_ID} NOT IN " +
                        "(SELECT ${ClipDbHelper.COL_ID} FROM ${ClipDbHelper.TABLE_CLIPS} " +
                        "ORDER BY ${ClipDbHelper.COL_TIMESTAMP} DESC LIMIT 20)"
            )

            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }

        return record
    }

    fun getClips(limit: Int = 20): List<ClipRecord> {
        val list = mutableListOf<ClipRecord>()
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            ClipDbHelper.TABLE_CLIPS,
            null,
            null,
            null,
            null,
            null,
            "${ClipDbHelper.COL_TIMESTAMP} DESC",
            limit.toString()
        )
        cursor.use {
            val idIdx = cursor.getColumnIndexOrThrow(ClipDbHelper.COL_ID)
            val textIdx = cursor.getColumnIndexOrThrow(ClipDbHelper.COL_TEXT)
            val hashIdx = cursor.getColumnIndexOrThrow(ClipDbHelper.COL_HASH)
            val srcIdx = cursor.getColumnIndexOrThrow(ClipDbHelper.COL_SOURCE)
            val timeIdx = cursor.getColumnIndexOrThrow(ClipDbHelper.COL_TIMESTAMP)

            while (cursor.moveToNext()) {
                list.add(
                    ClipRecord(
                        id = cursor.getString(idIdx),
                        text = cursor.getString(textIdx),
                        hash = cursor.getString(hashIdx),
                        source = cursor.getString(srcIdx),
                        timestamp = cursor.getLong(timeIdx)
                    )
                )
            }
        }
        return list
    }

    fun deleteClip(id: String) {
        val db = dbHelper.writableDatabase
        db.delete(ClipDbHelper.TABLE_CLIPS, "${ClipDbHelper.COL_ID} = ?", arrayOf(id))
    }

    fun clearClips() {
        val db = dbHelper.writableDatabase
        db.delete(ClipDbHelper.TABLE_CLIPS, null, null)
    }

    private class ClipDbHelper(context: Context) :
        SQLiteOpenHelper(context, "sync47_clips.db", null, 1) {

        companion object {
            const val TABLE_CLIPS = "clips"
            const val COL_ID = "id"
            const val COL_TEXT = "text"
            const val COL_HASH = "hash"
            const val COL_SOURCE = "source"
            const val COL_TIMESTAMP = "timestamp"
        }

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE $TABLE_CLIPS (
                    $COL_ID TEXT PRIMARY KEY,
                    $COL_TEXT TEXT NOT NULL,
                    $COL_HASH TEXT NOT NULL,
                    $COL_SOURCE TEXT NOT NULL,
                    $COL_TIMESTAMP INTEGER NOT NULL
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX idx_clips_timestamp ON $TABLE_CLIPS ($COL_TIMESTAMP DESC)")
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            db.execSQL("DROP TABLE IF EXISTS $TABLE_CLIPS")
            onCreate(db)
        }
    }
}
