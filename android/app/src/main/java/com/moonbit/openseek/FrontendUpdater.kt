package com.moonbit.openseek

import android.content.Context
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Keeps the app on the frontend that browsers get. Whenever the app comes to
 * the foreground, at most once per [CHECK_INTERVAL_MS], it reads which Browser
 * release openseek-api selects; a different one is downloaded and extracted
 * in the background, and the app runs it from the next time it creates its
 * WebView. Failures stay in the log: the app keeps the frontend it has.
 */
internal object FrontendUpdater {
    private const val TAG = "FrontendUpdater"
    private const val CHECK_INTERVAL_MS = 30 * 60 * 1000L

    private var store: FrontendStore? = null
    private var lastCheck: Long? = null
    private val busy = AtomicBoolean(false)

    /** This process's store of downloaded frontends. Main thread only. */
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

    /** Starts a background check unless one ran recently. Main thread only. */
    fun onStart(context: Context) {
        if (!BuildConfig.FRONTEND_UPDATES) return
        val now = SystemClock.elapsedRealtime()
        lastCheck?.let { if (now - it < CHECK_INTERVAL_MS) return }
        if (!busy.compareAndSet(false, true)) return
        lastCheck = now
        val store = store(context)
        thread(name = "frontend-update", isDaemon = true) {
            try {
                store.prune()
                val release = get(FrontendUpdate.CURRENT_URL) { FrontendUpdate.currentRelease(it.bufferedReader().readText()) }
                if (store.wants(release) && !store.select(release)) {
                    val adopted = get(FrontendUpdate.archiveUrl(release)) { store.install(release, it) }
                    Log.i(TAG, if (adopted) "frontend $release is ready" else "frontend $release needs a newer app")
                }
            } catch (e: Exception) {
                Log.w(TAG, "frontend update failed", e)
            } finally {
                busy.set(false)
            }
        }
    }

    private fun <T> get(url: String, read: (InputStream) -> T): T {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) throw IOException("$url answered HTTP $code")
            return connection.inputStream.use(read)
        } finally {
            connection.disconnect()
        }
    }
}
