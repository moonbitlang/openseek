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
 * the foreground, at most once per [CHECK_INTERVAL_MS], and whenever a
 * download completes, one background job reads which Browser release
 * openseek-api selects and acts on it:
 *
 * - A completed download of that release is verified against the selection's
 *   SHA-256 and extracted; the app runs it from the next time it creates its
 *   WebView. A download of any other release is discarded.
 * - A different release is fetched by the system download manager, silently
 *   and only on an unmetered network; it resumes across network loss and
 *   process death. A selection without a digest is never downloaded.
 *
 * Jobs never overlap, so a download is always judged against a fresh
 * selection. Failures stay in the log: the app keeps the frontend it has.
 */
internal class FrontendUpdater(private val activity: Activity) {
    /** A download this app enqueued and has not yet extracted. */
    private data class Pending(val id: Long, val release: String)

    // Lazy: the activity constructs this before it has a context.
    private val downloads by lazy { activity.getSystemService(DownloadManager::class.java) }
    private val prefs by lazy { activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    private val downloadComplete = object : BroadcastReceiver() {
        // Anyone can send this action; the job asks the download manager itself.
        override fun onReceive(context: Context, intent: Intent) {
            if (pending() != null) run()
        }
    }

    fun onStart() {
        if (!BuildConfig.FRONTEND_UPDATES) return
        // The download manager is another app, so the receiver must be exported.
        ContextCompat.registerReceiver(
            activity, downloadComplete,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), ContextCompat.RECEIVER_EXPORTED
        )
        val due = lastCheck?.let { SystemClock.elapsedRealtime() - it >= CHECK_INTERVAL_MS } ?: true
        if (due || pending()?.let { status(it)?.first == DownloadManager.STATUS_SUCCESSFUL } == true) run()
    }

    fun onStop() {
        if (BuildConfig.FRONTEND_UPDATES) activity.unregisterReceiver(downloadComplete)
    }

    /** Starts the job unless one is running. Main thread only. */
    private fun run() {
        val archives = archivesDir() ?: return
        if (!busy.compareAndSet(false, true)) return
        lastCheck = SystemClock.elapsedRealtime()
        val store = store(activity)
        thread(name = "frontend-update", isDaemon = true) {
            try {
                store.prune()
                update(store, currentRelease(), archives)
            } catch (e: Exception) {
                Log.w(TAG, "frontend update failed", e)
            } finally {
                busy.set(false)
            }
        }
    }

    private fun update(store: FrontendStore, current: FrontendUpdate.Current, archives: File) {
        pending()?.let { pending ->
            val row = status(pending)
            when {
                // Removed by the user or failed for good: the next due check
                // retries, not this job, which the failure itself started.
                row == null || row.first == DownloadManager.STATUS_FAILED -> {
                    discard(pending)
                    return
                }
                pending.release != current.release -> discard(pending)
                row.first == DownloadManager.STATUS_SUCCESSFUL -> {
                    clearPending()
                    val archive = row.second?.toUri()?.path?.let(::File)
                    try {
                        if (archive != null && current.sha256 != null && store.wants(current.release)) {
                            val adopted = archive.inputStream().use { store.install(current.release, current.sha256, it) }
                            Log.i(TAG, if (adopted) "frontend ${current.release} is ready" else "frontend ${current.release} needs a newer app")
                        }
                    } finally {
                        archive?.delete()
                    }
                    return
                }
                // Still downloading the selected release.
                else -> return
            }
        }
        // A refused, abandoned or discarded archive is never read again.
        archives.listFiles()?.forEach { it.delete() }
        if (store.wants(current.release) && !store.select(current.release) && current.sha256 != null) {
            enqueue(current.release)
        }
    }

    /** The download's status and local URI, or null once the user removed it. */
    private fun status(pending: Pending): Pair<Int, String?>? =
        downloads.query(DownloadManager.Query().setFilterById(pending.id)).use { cursor ->
            if (!cursor.moveToFirst()) null
            else cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) to
                cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
        }

    private fun currentRelease(): FrontendUpdate.Current {
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
