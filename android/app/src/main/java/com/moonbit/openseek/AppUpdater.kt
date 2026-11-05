package com.moonbit.openseek

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Self-update for the release APK, the Android counterpart of Desktop's
 * updater: check the release manifest once per launch, download and verify
 * a newer APK in the background, then offer to install it. Android requires
 * the user to confirm an installation from this source, so installing always
 * starts from the "Install" button; on Android 12+ the system may skip its own
 * confirmation once this app installed the current version itself.
 *
 * Debug builds have their own application ID and never update to the release.
 */
internal class AppUpdater(private val activity: Activity) {
    // Lazy: the activity constructs this before it has a context.
    private val dir by lazy { File(activity.cacheDir, "updates") }
    private var awaitingPermission: File? = null

    /** Starts a background check; the offer appears when a verified APK is ready. */
    fun start() {
        if (BuildConfig.DEBUG) return
        thread(name = "app-update", isDaemon = true) {
            val ready = try {
                prepare()
            } catch (e: Exception) {
                // A nudge, not a feature: offline and server failures stay quiet.
                Log.w(TAG, "update check failed", e)
                null
            }
            if (ready != null) activity.runOnUiThread { offer(ready.first, ready.second) }
        }
    }

    /**
     * Android may destroy the activity, or the whole process, while the user
     * is in Settings granting "install unknown apps". The pending APK stays in
     * the cache; its path travels in the saved state so [onResume] continues.
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

    private fun prepare(): Pair<String, File>? {
        val manifest = get(AppUpdate.MANIFEST_URL) { it.bufferedReader().readText() }
        val release = AppUpdate.newerRelease(manifest, BuildConfig.VERSION_NAME)
        dir.mkdirs()
        val target = release?.let { File(dir, "SeekMoon-${it.version}.apk") }
        // Only the pending release is kept; an installed or superseded APK is debris.
        dir.listFiles()?.forEach { if (it != target) it.delete() }
        if (release == null || target == null) return null
        if (target.isFile && target.inputStream().use { AppUpdate.copyWithSha256(it, null) } == release.sha256) {
            return release.version to target
        }
        val partial = File(dir, "${target.name}.part")
        val digest = get(release.url) { input ->
            partial.outputStream().use { AppUpdate.copyWithSha256(input, it) }
        }
        if (digest != release.sha256) {
            partial.delete()
            throw IOException("the downloaded APK does not match the manifest's SHA-256")
        }
        if (!partial.renameTo(target)) throw IOException("could not stage the downloaded APK")
        return release.version to target
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

    private fun offer(version: String, apk: File) {
        if (activity.isFinishing || activity.isDestroyed) return
        AlertDialog.Builder(activity)
            .setTitle("Update available")
            .setMessage("Version $version has been downloaded. Install it now? The app restarts after installing.")
            .setPositiveButton("Install") { _, _ -> install(apk) }
            .setNegativeButton("Later", null)
            .show()
    }

    private fun install(apk: File) {
        if (!activity.packageManager.canRequestPackageInstalls()) {
            awaitingPermission = apk
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
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
