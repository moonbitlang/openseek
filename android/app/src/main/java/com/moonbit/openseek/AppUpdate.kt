package com.moonbit.openseek

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import org.json.JSONException
import org.json.JSONObject

/**
 * The release manifest contract shared with Desktop. The release workflow
 * publishes one `latest.json` per release; its `platforms.android` entry names
 * the signed APK and its SHA-256. Pure, so unit tests cover the contract
 * without a device or a server.
 */
internal object AppUpdate {
    /** The same manifest Desktop checks (`desktop/backend/update/update.mbt`). */
    const val MANIFEST_URL = "https://seekmoon.moonbitlang.com/desktop/releases/latest.json"
    const val PLATFORM = "android"

    data class Release(val version: String, val url: String, val sha256: String)

    /** The server answered with a manifest that cannot be used. */
    class MalformedManifest(message: String) : Exception(message)

    private val versionPattern = Regex("""(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)""")
    private val sha256Pattern = Regex("[0-9a-fA-F]{64}")

    /** `major.minor.patch`, the only shape the release workflow stamps. */
    fun parseVersion(version: String): List<Int>? =
        versionPattern.matchEntire(version)?.groupValues?.drop(1)?.map { it.toIntOrNull() ?: return null }

    /** True exactly when [candidate] is a strictly newer release than [current]. */
    fun isNewer(candidate: String, current: String): Boolean {
        val next = parseVersion(candidate) ?: return false
        val installed = parseVersion(current) ?: return false
        for (i in next.indices) {
            if (next[i] != installed[i]) return next[i] > installed[i]
        }
        return false
    }

    /**
     * The release to install, or null when the manifest names nothing newer
     * or no APK (releases predating Android have none). An Android entry that
     * is present but unusable is the publisher's fault and raises.
     */
    fun newerRelease(manifest: String, current: String): Release? {
        val root = try {
            JSONObject(manifest)
        } catch (e: JSONException) {
            throw MalformedManifest("the manifest is not valid JSON")
        }
        val version = root.optString("version")
        if (parseVersion(version) == null) throw MalformedManifest("the manifest has no valid version")
        if (!isNewer(version, current)) return null
        val entry = root.optJSONObject("platforms")?.opt(PLATFORM) ?: return null
        if (entry !is JSONObject) throw MalformedManifest("the $PLATFORM entry is not an object")
        val url = entry.optString("url")
        if (!url.startsWith("https://")) throw MalformedManifest("the $PLATFORM entry has no HTTPS url")
        val sha256 = entry.optString("sha256")
        if (!sha256Pattern.matches(sha256)) throw MalformedManifest("the $PLATFORM entry has no valid sha256")
        return Release(version, url, sha256.lowercase())
    }

    /** Copies [input] to [output] and returns the lowercase hex SHA-256 of the bytes. */
    fun copyWithSha256(input: InputStream, output: OutputStream?): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
            output?.write(buffer, 0, read)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
