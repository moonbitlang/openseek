package com.moonbit.openseek

import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Self-update for the release APK, the Android counterpart of Desktop's
 * updater: check the release manifest whenever the app comes to the
 * foreground, at most once per [CHECK_INTERVAL_MS]. When a newer APK exists,
 * offer to update; the system download manager fetches it (progress in the
 * notification shade, retries and resumes across network loss and process
 * death), and when the download completes while the app is in the
 * foreground, or on the next return to it, the app verifies the SHA-256 and
 * hands the APK to the installer. Android requires the user to confirm an
 * installation from this source; on Android 12+ the system may skip its own
 * confirmation once this app installed the current version itself.
 *
 * Debug builds have their own application ID and never update to the release.
 */
internal class AppUpdater(private val activity: Activity) {
    /** A download this app enqueued and has not yet handed to the installer. */
    private data class Pending(val id: Long, val version: String, val sha256: String)

    // Lazy: the activity constructs this before it has a context.
    private val downloads by lazy { activity.getSystemService(DownloadManager::class.java) }
    private val prefs by lazy { activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }
    private var awaitingPermission: File? = null
    private var offerDialog: AlertDialog? = null
    private val downloadComplete = object : BroadcastReceiver() {
        // Anyone can send this action; the download manager's own record decides.
        override fun onReceive(context: Context, intent: Intent) = finishDownload()
    }

    fun onStart() {
        // The download manager is another app, so the receiver must be exported.
        ContextCompat.registerReceiver(
            activity, downloadComplete,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), ContextCompat.RECEIVER_EXPORTED
        )
        finishDownload()
        checkIfDue()
    }

    fun onStop() {
        activity.unregisterReceiver(downloadComplete)
    }

    /**
     * Starts a background check unless one started within [CHECK_INTERVAL_MS].
     * Runs on every return to the foreground: a phone keeps the app alive for
     * days, so checking only on a cold start misses releases.
     */
    private fun checkIfDue() {
        if (BuildConfig.DEBUG || awaitingPermission != null) return
        val now = SystemClock.elapsedRealtime()
        lastCheck?.let { if (now - it < CHECK_INTERVAL_MS) return }
        lastCheck = now
        thread(name = "app-update", isDaemon = true) {
            val release = try {
                AppUpdate.newerRelease(fetchManifest(), BuildConfig.VERSION_NAME)
            } catch (e: Exception) {
                // A nudge, not a feature: offline and server failures stay quiet.
                Log.w(TAG, "update check failed", e)
                return@thread
            }
            activity.runOnUiThread { consider(release) }
        }
    }

    private fun fetchManifest(): String {
        val connection = URL(AppUpdate.MANIFEST_URL).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) throw IOException("the manifest answered HTTP $code")
            return connection.inputStream.use { it.bufferedReader().readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun consider(release: AppUpdate.Release?) {
        val pending = pending()
        // A download of this very release finishes on its own.
        if (release != null && pending?.version == release.version) return
        pending?.let { discard(it) }
        if (release != null) {
            offer(release)
        } else {
            // Up to date: any downloaded APK is installed or superseded.
            updatesDir()?.listFiles()?.forEach { it.delete() }
        }
    }

    private fun offer(release: AppUpdate.Release) {
        if (activity.isFinishing || activity.isDestroyed || offerDialog?.isShowing == true) return
        offerDialog = AlertDialog.Builder(activity)
            .setTitle("Update available")
            .setMessage("Version ${release.version} is available. Download and install it now? SeekMoon closes while it installs; open it again afterwards.")
            .setPositiveButton("Update") { _, _ -> download(release) }
            .setNegativeButton("Later", null)
            .show()
    }

    private fun download(release: AppUpdate.Release) {
        if (updatesDir() == null) {
            Toast.makeText(activity, "Unable to download the update", Toast.LENGTH_LONG).show()
            return
        }
        val request = DownloadManager.Request(release.url.toUri())
            .setTitle("SeekMoon ${release.version}")
            .setMimeType(APK_MIME_TYPE)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(activity, UPDATES_DIR, "SeekMoon-${release.version}.apk")
        val id = downloads.enqueue(request)
        prefs.edit {
            putLong(KEY_ID, id)
            putString(KEY_VERSION, release.version)
            putString(KEY_SHA256, release.sha256)
        }
        Toast.makeText(activity, "Downloading the update", Toast.LENGTH_SHORT).show()
    }

    /** Hands a completed download to the installer, or reports a failed one. */
    private fun finishDownload() {
        val pending = pending() ?: return
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
                val apk = row.second.toUri().path?.let(::File) ?: return
                thread(name = "app-update-verify") {
                    val digest = try {
                        apk.inputStream().use { AppUpdate.copyWithSha256(it, null) }
                    } catch (e: IOException) {
                        Log.w(TAG, "reading the downloaded update failed", e)
                        null
                    }
                    activity.runOnUiThread {
                        if (digest != pending.sha256) {
                            apk.delete()
                            Toast.makeText(activity, "The downloaded update is damaged", Toast.LENGTH_LONG).show()
                        } else if (!activity.isFinishing && !activity.isDestroyed) {
                            install(apk)
                        }
                    }
                }
            }
            DownloadManager.STATUS_FAILED -> {
                discard(pending)
                Toast.makeText(activity, "Unable to download the update", Toast.LENGTH_LONG).show()
            }
            else -> Unit
        }
    }

    private fun pending(): Pending? {
        if (!prefs.contains(KEY_ID)) return null
        val version = prefs.getString(KEY_VERSION, null) ?: return null
        val sha256 = prefs.getString(KEY_SHA256, null) ?: return null
        return Pending(prefs.getLong(KEY_ID, 0), version, sha256)
    }

    /** Cancels the download and deletes its file. */
    private fun discard(pending: Pending) {
        downloads.remove(pending.id)
        clearPending()
    }

    private fun clearPending() {
        prefs.edit { clear() }
    }

    private fun updatesDir(): File? = activity.getExternalFilesDir(UPDATES_DIR)

    /**
     * Android may destroy the activity, or the whole process, while the user
     * is in Settings granting "install unknown apps". The verified APK stays
     * in place; its path travels in the saved state so [onResume] continues.
     */
    fun saveState(outState: Bundle) {
        awaitingPermission?.let { outState.putString(AWAITING_PERMISSION, it.path) }
    }

    fun restoreState(savedState: Bundle?) {
        val path = savedState?.getString(AWAITING_PERMISSION) ?: return
        awaitingPermission = File(path).takeIf { it.isFile }
    }

    /** Resumes an installation that was waiting for the "install unknown apps" setting. */
    fun onResume() {
        val apk = awaitingPermission ?: return
        awaitingPermission = null
        if (activity.packageManager.canRequestPackageInstalls()) {
            install(apk)
        } else {
            Toast.makeText(activity, "Allow installs from SeekMoon to update it", Toast.LENGTH_LONG).show()
        }
    }

    private fun install(apk: File) {
        if (!activity.packageManager.canRequestPackageInstalls()) {
            awaitingPermission = apk
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, "package:${activity.packageName}".toUri())
            )
            return
        }
        val context = activity.applicationContext
        thread(name = "app-update-install") {
            try {
                commit(context, apk)
            } catch (e: Exception) {
                Log.w(TAG, "update install failed", e)
                activity.runOnUiThread {
                    Toast.makeText(context, "Unable to install the update", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun commit(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val id = installer.createSession(params)
        try {
            installer.openSession(id).use { session ->
                session.openWrite("base.apk", 0, apk.length()).use { out ->
                    apk.inputStream().use { it.copyTo(out) }
                    session.fsync(out)
                }
                // The installer adds its status extras to this intent, so it must be mutable.
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                val result = PendingIntent.getBroadcast(
                    context, id, Intent(context, InstallResultReceiver::class.java), flags
                )
                session.commit(result.intentSender)
            }
        } catch (e: Exception) {
            installer.abandonSession(id)
            throw e
        }
    }

    companion object {
        private const val TAG = "AppUpdater"
        private const val AWAITING_PERMISSION = "appUpdater.awaitingPermission"
        private const val CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000L
        private const val UPDATES_DIR = "updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PREFS = "app_update"
        private const val KEY_ID = "download_id"
        private const val KEY_VERSION = "version"
        private const val KEY_SHA256 = "sha256"

        // Process-wide, so recreating the activity does not check again; a
        // new process checks on its first foreground. Main thread only.
        private var lastCheck: Long? = null
    }
}

/** Receives the installer's status for a committed update session. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            // Success replaces this process; an abort is the user declining.
            PackageInstaller.STATUS_SUCCESS, PackageInstaller.STATUS_FAILURE_ABORTED -> Unit
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.w("AppUpdater", "update install failed: $message")
                Toast.makeText(context, "Unable to install the update", Toast.LENGTH_LONG).show()
            }
        }
    }
}
