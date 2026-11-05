package com.moonbit.openseek

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.*
import org.junit.Test

class AppUpdateTest {
    private val sha = "84AFC9BD960C0B7BE57E711F1BE15D9278887A0F730E11AA510D95CD1C7506F9"

    private fun manifest(version: String = "0.2.37", android: String? =
        """{"url":"https://seekmoon.moonbitlang.com/desktop/releases/v$version/SeekMoon-android.apk","sha256":"$sha"}"""
    ) = """{"version":"$version","url":"https://github.com/moonbitlang/openseek/releases/latest",
        "platforms":{"macos-arm64":{"url":"https://example.com/a.zip","sha256":"$sha"}
        ${if (android != null) ""","android":$android""" else ""}}}"""

    @Test fun versionsCompareNumericallyByComponent() {
        assertTrue(AppUpdate.isNewer("0.2.37", "0.2.36"))
        assertTrue(AppUpdate.isNewer("0.2.10", "0.2.9"))
        assertTrue(AppUpdate.isNewer("1.0.0", "0.99.99"))
        assertFalse(AppUpdate.isNewer("0.2.37", "0.2.37"))
        assertFalse(AppUpdate.isNewer("0.2.36", "0.2.37"))
        assertFalse(AppUpdate.isNewer("0.3.0", "0.3.0-debug"))
        assertFalse(AppUpdate.isNewer("v0.3.0", "0.2.0"))
        assertFalse(AppUpdate.isNewer("0.03.0", "0.2.0"))
    }

    @Test fun aNewerReleaseWithAnApkIsReturnedNormalized() {
        assertEquals(
            AppUpdate.Release(
                "0.2.37",
                "https://seekmoon.moonbitlang.com/desktop/releases/v0.2.37/SeekMoon-android.apk",
                sha.lowercase(),
            ),
            AppUpdate.newerRelease(manifest(), "0.2.36"),
        )
    }

    @Test fun nothingNewerOrNoApkIsNoUpdate() {
        assertNull(AppUpdate.newerRelease(manifest(), "0.2.37"))
        assertNull(AppUpdate.newerRelease(manifest(), "0.3.0"))
        assertNull(AppUpdate.newerRelease(manifest(android = null), "0.2.0"))
    }

    @Test fun unusableManifestsRaise() {
        for (body in listOf(
            "<html>captive portal</html>",
            """{"platforms":{}}""",
            manifest(version = "latest"),
            manifest(android = "\"SeekMoon-android.apk\""),
            manifest(android = """{"url":"http://example.com/a.apk","sha256":"$sha"}"""),
            manifest(android = """{"url":"https://example.com/a.apk"}"""),
            manifest(android = """{"url":"https://example.com/a.apk","sha256":"abc"}"""),
        )) {
            assertThrows(body, AppUpdate.MalformedManifest::class.java) {
                AppUpdate.newerRelease(body, "0.2.0")
            }
        }
    }

    @Test fun copyingReportsTheSha256OfTheBytes() {
        val out = ByteArrayOutputStream()
        val digest = AppUpdate.copyWithSha256(ByteArrayInputStream("abc".toByteArray()), out)
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", digest)
        assertEquals("abc", out.toString())
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            AppUpdate.copyWithSha256(ByteArrayInputStream(ByteArray(0)), null),
        )
    }
}
