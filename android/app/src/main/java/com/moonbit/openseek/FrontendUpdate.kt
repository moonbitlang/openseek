package com.moonbit.openseek

import org.json.JSONException
import org.json.JSONObject

/**
 * The contract for running the frontend openseek-api serves at /cloud rather
 * than only the APK's own. `current.json` names the selected Browser release,
 * a Desktop release (`0.2.52`) or a console-only one (`browser-3.1`); the two
 * kinds share no order, so the shell follows whichever the server selects,
 * rollbacks included. Pure, so unit tests cover it without a device.
 */
internal object FrontendUpdate {
    const val CURRENT_URL = "${ConsoleOrigin.ORIGIN}/browser/releases/current.json"

    /** The bundle's declaration of the oldest APK release whose shell it works with. */
    const val REQUIREMENT = "android.json"

    /** One path segment, as openseek-api names release directories. */
    private val releasePattern = Regex("[A-Za-z0-9][A-Za-z0-9._-]*")

    private val sha256Pattern = Regex("[0-9a-f]{64}")

    /** The server answered with a release pointer that cannot be used. */
    class MalformedRelease(message: String) : Exception(message)

    /**
     * The selected release and its archive's SHA-256. Pointers published
     * before openseek-api recorded the digest have none, and their archives
     * are never downloaded: nothing else authenticates them.
     */
    data class Current(val release: String, val sha256: String?)

    fun currentRelease(json: String): Current {
        val root = try {
            JSONObject(json)
        } catch (e: JSONException) {
            throw MalformedRelease("the current release is not valid JSON")
        }
        val release = root.optString("version")
        if (!releasePattern.matches(release)) throw MalformedRelease("the current release has no valid version")
        val sha256 = when (val digest = root.opt("sha256")) {
            null, JSONObject.NULL -> null
            is String -> digest.takeIf { sha256Pattern.matches(it) }
                ?: throw MalformedRelease("the current release has no valid sha256")
            else -> throw MalformedRelease("the current release has no valid sha256")
        }
        return Current(release, sha256)
    }

    /** Where openseek-api keeps each Browser release's uploaded archive. */
    fun archiveUrl(release: String): String =
        "${ConsoleOrigin.ORIGIN}/desktop/releases/v$release/SeekMoon.browser.tar.gz"

    /**
     * Whether a bundle declaring [requirement] runs on the shell of APK
     * release [shell]. A bundle without a valid declaration predates frontend
     * updates and is never adopted.
     */
    fun admits(requirement: String?, shell: String): Boolean {
        val minimum = try {
            requirement?.let { JSONObject(it).optString("min_android_version") }
        } catch (e: JSONException) {
            null
        } ?: return false
        if (AppUpdate.parseVersion(minimum) == null || AppUpdate.parseVersion(shell) == null) return false
        return !AppUpdate.isNewer(minimum, shell)
    }
}
