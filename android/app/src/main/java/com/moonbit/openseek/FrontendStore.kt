package com.moonbit.openseek

import java.io.File
import java.io.IOException
import java.io.InputStream

/**
 * The Browser releases downloaded for the APK release [shell], under
 * `<parent>/<shell>/`. The APK's own bundle is release [shell] and needs no
 * directory. `current` names the release the WebView runs and `next` the one
 * it switches to the next time the app creates its WebView, so one page never
 * mixes two releases' files. Another APK release starts again from its own
 * bundle: [prune] deletes every other APK release's directory.
 *
 * The activity and the update thread share one instance per process.
 */
internal class FrontendStore(private val parent: File, val shell: String) {
    private val root = File(parent, shell)
    private val releases = File(root, "releases")
    private val lock = Any()

    /** The release this process's WebView runs; set by [activate]. */
    private var running: String? = null

    /**
     * Switches to the `next` release and returns the directory to serve the
     * frontend from, or null for the APK's own bundle.
     */
    fun activate(): File? = synchronized(lock) {
        read(NEXT)?.let { next ->
            write(CURRENT, next)
            File(root, NEXT).delete()
        }
        val current = read(CURRENT)?.takeIf { it != shell }
        val directory = current?.let { File(releases, it) }?.takeIf { complete(it) }
        if (current != null && directory == null) File(root, CURRENT).delete()
        running = directory?.name ?: shell
        directory
    }

    /**
     * Deletes the releases that neither run nor wait, and every other APK
     * release's directory. Off the main thread: a release has hundreds of files.
     */
    fun prune() = synchronized(lock) {
        parent.listFiles()?.forEach { if (it.name != shell) it.deleteRecursively() }
        val kept = setOfNotNull(running, read(NEXT))
        releases.listFiles()?.forEach { if (it.name !in kept) it.deleteRecursively() }
    }

    /** Whether the app should move to [release]: it neither runs, waits, nor was refused. */
    fun wants(release: String): Boolean = synchronized(lock) {
        val target = read(NEXT) ?: running ?: read(CURRENT) ?: shell
        release != target && release != read(REFUSED)
    }

    /**
     * Makes [release] `next` when it needs no download: it is the APK's own
     * bundle, or the release this process already runs. Returns whether it did.
     */
    fun select(release: String): Boolean = synchronized(lock) {
        if (release != shell && !(release == running && complete(File(releases, release)))) return false
        write(NEXT, release)
        true
    }

    /**
     * Extracts [archive] as [release] and makes it `next`, unless the bundle
     * declares that it needs a newer APK; that release is then remembered as
     * refused and never downloaded again. Returns whether it was adopted.
     * One call at a time.
     */
    fun install(release: String, archive: InputStream): Boolean {
        val partial = File(root, "partial")
        partial.deleteRecursively()
        partial.mkdirs()
        BundleArchive.extract(archive, partial)
        if (!complete(partial)) throw BundleArchive.Malformed("the archive has no index.html and frontend.js")
        val requirement = File(partial, FrontendUpdate.REQUIREMENT).takeIf { it.isFile }?.readText()
        if (!FrontendUpdate.admits(requirement, shell)) {
            partial.deleteRecursively()
            synchronized(lock) { write(REFUSED, release) }
            return false
        }
        synchronized(lock) {
            val directory = File(releases, release)
            directory.deleteRecursively()
            releases.mkdirs()
            if (!partial.renameTo(directory)) throw IOException("unable to keep release $release")
            write(NEXT, release)
        }
        return true
    }

    private fun complete(directory: File) =
        File(directory, "index.html").isFile && File(directory, "assets/frontend.js").isFile

    private fun read(name: String): String? = File(root, name).takeIf { it.isFile }?.readText()

    /** Replaces the pointer by a rename, so a killed process leaves the old or the new one. */
    private fun write(name: String, release: String) {
        root.mkdirs()
        val temporary = File(root, "$name.tmp")
        temporary.writeText(release)
        if (!temporary.renameTo(File(root, name))) throw IOException("unable to record $name")
    }

    companion object {
        private const val CURRENT = "current"
        private const val NEXT = "next"
        private const val REFUSED = "refused"
    }
}
