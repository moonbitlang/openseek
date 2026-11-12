package com.moonbit.openseek

import android.app.Activity
import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Keeps the app on the frontend that browsers get. Whenever the app comes to
 * the foreground, at most once per [CHECK_INTERVAL_MS], it reads which Browser
 * release openseek-api selects. A different one is fetched by the system
 * download manager, silently and only on an unmetered network; it resumes
 * across network loss and process death. Once the download is complete and
 * the app is in the foreground, a background thread extracts it, and the app
 * runs it from the next time it creates its WebView. Failures stay in the
 * log: the app keeps the frontend it has.
 */
internal class FrontendUpdater(private val activity: Activity) {
    /** A download this app enqueued and has not yet extracted. */
    private data class Pending(val id: Long, val release: String)

    // Lazy: the activity constructs this before it has a context.
    private val downloads by lazy { activity.getSystemService(DownloadManager::class.java) }
    private val prefs by lazy { activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    private val downloadComplete = object : BroadcastReceiver() {
        // Anyone can send this action; the download manager's own record decides.
        override fun onReceive(context: Context, intent: Intent) = finishDownload()
    }

    fun onStart() {
        if (!BuildConfig.FRONTEND_UPDATES) return
        // The download manager is another app, so the receiver must be exported.
        ContextCompat.registerReceiver(
            activity, downloadComplete,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), ContextCompat.RECEIVER_EXPORTED
        )
        finishDownload()
        checkIfDue()
    }

    fun onStop() {
        if (BuildConfig.FRONTEND_UPDATES) activity.unregisterReceiver(downloadComplete)
    }

    private fun checkIfDue() {
        val now = SystemClock.elapsedRealtime()
        lastCheck?.let { if (now - it < CHECK_INTERVAL_MS) return }
        val archives = archivesDir() ?: return
        if (!busy.compareAndSet(false, true)) return
        lastCheck = now
        val store = store(activity)
        thread(name = "frontend-update", isDaemon = true) {
            try {
                store.prune()
                val release = currentRelease()
                val pending = pending()
                if (pending?.release == release) return@thread
                pending?.let(::discard)
                // A refused or abandoned archive is never read again.
                archives.listFiles()?.forEach { it.delete() }
                if (store.wants(release) && !store.select(release)) enqueue(release)
            } catch (e: Exception) {
                Log.w(TAG, "frontend update check failed", e)
            } finally {
                busy.set(false)
            }
        }
    }

    private fun currentRelease(): String {
        val connection = URL(FrontendUpdate.CURRENT_URL).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) throw IOException("the current release answered HTTP $code")
            return FrontendUpdate.currentRelease(connection.inputStream.use { it.bufferedReader().readText() })
        } finally {
            connection.disconnect()
        }
    }

    private fun enqueue(release: String) {
        val request = DownloadManager.Request(FrontendUpdate.archiveUrl(release).toUri())
            .setTitle("SeekMoon frontend $release")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN)
            .setAllowedOverMetered(false)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalFilesDir(activity, ARCHIVES_DIR, "$release.tar.gz")
        val id = downloads.enqueue(request)
        prefs.edit {
            putLong(KEY_ID, id)
            putString(KEY_RELEASE, release)
        }
    }

    /**
     * Extracts a completed download in the background, or drops a failed one.
     * While a check or an earlier extraction holds [busy], the next start retries.
     */
    private fun finishDownload() {
        if (!busy.compareAndSet(false, true)) return
        var extracting = false
        try {
            extracting = finish()
        } finally {
            if (!extracting) busy.set(false)
        }
    }

    /** Returns whether an extraction thread took over [busy]. */
    private fun finish(): Boolean {
        val pending = pending() ?: return false
        val row = downloads.query(DownloadManager.Query().setFilterById(pending.id)).use { cursor ->
            if (!cursor.moveToFirst()) null
            else cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) to
                cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
        }
        when (row?.first) {
            // The user removed the download from the download manager.
            null -> clearPending()
            DownloadManager.STATUS_SUCCESSFUL -> {
                clearPending()
                val archive = row.second?.toUri()?.path?.let(::File)
                val store = store(activity)
                thread(name = "frontend-extract", isDaemon = true) {
                    try {
                        if (archive != null && store.wants(pending.release)) {
                            val adopted = archive.inputStream().use { store.install(pending.release, it) }
                            Log.i(TAG, if (adopted) "frontend ${pending.release} is ready" else "frontend ${pending.release} needs a newer app")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "extracting frontend ${pending.release} failed", e)
                    } finally {
                        archive?.delete()
                        busy.set(false)
                    }
                }
                return true
            }
            DownloadManager.STATUS_FAILED -> discard(pending)
            else -> Unit
        }
        return false
    }

    private fun pending(): Pending? {
        if (!prefs.contains(KEY_ID)) return null
        val release = prefs.getString(KEY_RELEASE, null) ?: return null
        return Pending(prefs.getLong(KEY_ID, 0), release)
    }

    /** Cancels the download and deletes its file. */
    private fun discard(pending: Pending) {
        downloads.remove(pending.id)
        clearPending()
    }

    private fun clearPending() {
        prefs.edit { clear() }
    }

    /** App-specific external storage, where the download manager may write. */
    private fun archivesDir(): File? = activity.getExternalFilesDir(ARCHIVES_DIR)

    companion object {
        private const val TAG = "FrontendUpdater"
        private const val CHECK_INTERVAL_MS = 30 * 60 * 1000L
        private const val ARCHIVES_DIR = "frontend"
        private const val PREFS = "frontend_update"
        private const val KEY_ID = "download_id"
        private const val KEY_RELEASE = "release"

        // Process-wide, so recreating the activity neither checks again nor
        // opens a second store. Main thread only, except [busy].
        private var store: FrontendStore? = null
        private var lastCheck: Long? = null
        private val busy = AtomicBoolean(false)

        /** This process's store of downloaded frontends. */
        fun store(context: Context): FrontendStore = store
            ?: FrontendStore(File(context.filesDir, "frontend"), BuildConfig.RELEASE_VERSION).also { store = it }

        /**
         * The directory to serve this WebView's frontend from, or null for the
         * APK's own bundle, which also serves when updates are off or the
         * downloaded release cannot be switched to.
         */
        fun activate(context: Context): File? {
            if (!BuildConfig.FRONTEND_UPDATES) return null
            return try {
                store(context).activate()
            } catch (e: IOException) {
                Log.w(TAG, "keeping the bundled frontend", e)
                null
            }
        }
    }
}
