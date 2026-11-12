package com.moonbit.openseek

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.GZIPOutputStream

class FrontendUpdateTest {
    @get:Rule val temp = TemporaryFolder()

    /** A Browser release archive as the release workflow packs it. */
    private fun archive(files: Map<String, String>): ByteArray {
        val root = temp.newFolder()
        for ((path, text) in files) File(root, "browser/$path").apply { parentFile.mkdirs() }.writeText(text)
        val out = File(temp.root, "browser-${System.nanoTime()}.tar.gz")
        val tar = ProcessBuilder("tar", "-C", root.path, "-czf", out.path, "browser").inheritIO().start()
        assertEquals(0, tar.waitFor())
        return out.readBytes()
    }

    private fun release(minimum: String = "0.2.51", script: String = "frontend") = archive(
        mapOf(
            "index.html" to "<script src=\"/assets/frontend.js\"></script>",
            "assets/frontend.js" to script,
            "assets/frontend.js.br" to "copy",
            FrontendUpdate.REQUIREMENT to """{"min_android_version":"$minimum"}""",
        )
    )

    @Test fun currentReleaseNamesOnePathSegment() {
        assertEquals("browser-3.1", FrontendUpdate.currentRelease("""{"version":"browser-3.1"}"""))
        assertEquals("0.2.52", FrontendUpdate.currentRelease("""{"version":"0.2.52"}"""))
        for (bad in listOf("""{"version":"../x"}""", """{"version":""}""", "{}", "nope")) {
            assertThrows(FrontendUpdate.MalformedRelease::class.java) { FrontendUpdate.currentRelease(bad) }
        }
        assertEquals(
            "https://seekmoon.moonbitlang.com/desktop/releases/vbrowser-3.1/SeekMoon.browser.tar.gz",
            FrontendUpdate.archiveUrl("browser-3.1"),
        )
    }

    @Test fun aBundleRunsOnlyOnTheShellItDeclares() {
        assertTrue(FrontendUpdate.admits("""{"min_android_version":"0.2.51"}""", "0.2.51"))
        assertTrue(FrontendUpdate.admits("""{"min_android_version":"0.2.51"}""", "0.3.0"))
        assertFalse(FrontendUpdate.admits("""{"min_android_version":"0.2.53"}""", "0.2.52"))
        assertFalse(FrontendUpdate.admits(null, "0.2.52"))
        assertFalse(FrontendUpdate.admits("{}", "0.2.52"))
        assertFalse(FrontendUpdate.admits("not json", "0.2.52"))
    }

    @Test fun extractionKeepsLongPathsAndDropsCompressedCopies() {
        val deep = "assets/vendor/pdfjs/web/" + "nested-directory/".repeat(6) + "a-file-with-a-long-name.js"
        val target = temp.newFolder()
        BundleArchive.extract(
            ByteArrayInputStream(archive(mapOf("index.html" to "doc", deep to "deep", "assets/app.css.gz" to "copy"))),
            target,
        )
        assertEquals("doc", File(target, "index.html").readText())
        assertEquals("deep", File(target, deep).readText())
        assertFalse(File(target, "assets/app.css.gz").exists())
    }

    @Test fun extractionRejectsEntriesOutsideTheBundle() {
        val header = ByteArray(512)
        "browser/../escaped".toByteArray().copyInto(header)
        "00000000000\u0000".toByteArray().copyInto(header, 124)
        header[156] = '0'.code.toByte()
        val gzip = ByteArrayOutputStream().also { out ->
            GZIPOutputStream(out).use { it.write(header + ByteArray(1024)) }
        }.toByteArray()
        assertThrows(BundleArchive.Malformed::class.java) {
            BundleArchive.extract(ByteArrayInputStream(gzip), temp.newFolder())
        }
    }

    @Test fun aTruncatedDownloadIsNotAdopted() {
        val bytes = release()
        val store = FrontendStore(temp.newFolder(), "0.2.52")
        store.activate()
        assertThrows(Exception::class.java) {
            store.install("browser-3.1", ByteArrayInputStream(bytes.copyOf(bytes.size - 16)))
        }
        assertNull(store.activate())
    }

    @Test fun aReleaseRunsFromTheNextWebViewAndTheServerCanReturnToTheBundle() {
        val parent = temp.newFolder()
        File(parent, "0.2.51/releases/old/index.html").apply { parentFile.mkdirs() }.writeText("old")
        val store = FrontendStore(parent, "0.2.52")
        assertNull(store.activate())
        store.prune()
        assertFalse(File(parent, "0.2.51").exists())

        assertFalse(store.wants("0.2.52"))
        assertTrue(store.wants("browser-3.1"))
        assertTrue(store.install("browser-3.1", ByteArrayInputStream(release(script = "hot"))))
        assertFalse(store.wants("browser-3.1"))

        val directory = store.activate()!!
        assertEquals("hot", File(directory, "assets/frontend.js").readText())
        assertFalse(File(directory, "assets/frontend.js.br").exists())
        assertEquals(directory, store.activate())

        // The server rolls back to the release this APK bundles.
        assertTrue(store.wants("0.2.52"))
        assertTrue(store.select("0.2.52"))
        assertNull(store.activate())
        store.prune()
        assertFalse(directory.exists())
    }

    @Test fun aReleaseNeedingANewerAppIsRefusedOnce() {
        val store = FrontendStore(temp.newFolder(), "0.2.52")
        store.activate()
        assertFalse(store.install("0.2.60", ByteArrayInputStream(release(minimum = "0.2.60"))))
        assertFalse(store.wants("0.2.60"))
        assertNull(store.activate())
    }
}
