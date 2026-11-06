package com.moonbit.openseek

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.webkit.URLUtil
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import java.io.File
import java.util.Base64
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Saves the downloads a page starts with `<a download href="blob:…">`, as a
 * browser does. WebView reports such a download to its DownloadListener but
 * cannot fetch a `blob:` URL natively, and reports no name: it forwards only a
 * response's Content-Disposition, never the anchor's `download` attribute.
 *
 * A document-start script on the application origin therefore remembers each
 * blob anchor the page activates, with its name, and starts reading the blob
 * at once, before the page may revoke its URL. When WebView then reports the
 * download, the script hands the bytes to this class, which asks where to
 * save them. The shell relies on the web platform's download anchor only,
 * never on the frontend's DOM.
 */
internal class BlobDownloads(private val activity: ComponentActivity, private val webView: WebView) {
    /** A download read from the page, staged in its own file until saved. */
    private class Staged(val file: File, val name: String, val type: String)

    private val directory = File(activity.cacheDir, "downloads")

    /**
     * Downloads waiting for the save dialog, which shows one at a time. The
     * page may start several before the first dialog opens.
     */
    private val queue = ArrayDeque<Staged>()

    /**
     * The file whose save dialog is open. Saved state carries it across the
     * activity's recreation, so the dialog's result still finds its bytes.
     */
    private var awaiting: File? = activity.savedStateRegistry.consumeRestoredStateForKey(STATE)
        ?.getString(AWAITING)?.let(::File)

    private val save = activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val file = awaiting
        awaiting = null
        val target = result.data?.data
        if (file != null) {
            if (result.resultCode == Activity.RESULT_OK && target != null) {
                staging.execute {
                    val saved = runCatching {
                        activity.contentResolver.openOutputStream(target, "wt")!!.use { output ->
                            file.inputStream().use { it.copyTo(output) }
                        }
                    }.isSuccess
                    file.delete()
                    activity.runOnUiThread { toast(if (saved) "Download saved" else "Unable to save the download") }
                }
            } else {
                staging.execute { file.delete() }
            }
        }
        next()
    }

    init {
        activity.savedStateRegistry.registerSavedStateProvider(STATE) {
            Bundle().apply { awaiting?.let { putString(AWAITING, it.path) } }
        }
        // Downloads still queued when a previous activity ended are dropped
        // with it; only an open save dialog's file is kept.
        val kept = awaiting
        staging.execute { directory.listFiles()?.filter { it != kept }?.forEach(File::delete) }
    }

    /**
     * A WebView too old to hand a page's blobs to the shell keeps doing nothing
     * on a blob download.
     */
    fun install() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        val origins = setOf(ConsoleOrigin.ORIGIN)
        WebViewCompat.addDocumentStartJavaScript(webView, SCRIPT, origins)
        WebViewCompat.addWebMessageListener(webView, CHANNEL, origins) { _, message, _, isMainFrame, _ ->
            if (isMainFrame) message.data?.let(::received)
        }
        webView.setDownloadListener { url, _, _, _, _ ->
            if (url.startsWith("blob:") && ConsoleOrigin.contains(webView.url)) {
                webView.evaluateJavascript("$SAVE(${JSONObject.quote(url)})", null)
            }
        }
    }

    /**
     * A download arriving from the page in chunks. The staging thread writes
     * [failed]; the UI thread reads it only in a callback that thread posts.
     */
    private class Receiving(val file: File) {
        @Volatile var failed = false
    }

    /** Downloads the page is still sending, by the page's id for each. */
    private val receiving = HashMap<String, Receiving>()

    /**
     * The page sends a download as base64 chunks, then an end message with its
     * name and type, so no whole-file copy is held in memory: Cloud files are
     * downloaded without a size limit.
     */
    private fun received(raw: String) {
        val message = JSONObject(raw)
        val id = message.getString("id")
        when {
            message.has("data") -> {
                val download = receiving.getOrPut(id) { Receiving(File(directory, UUID.randomUUID().toString())) }
                val data = message.getString("data")
                staging.execute {
                    if (download.failed) return@execute
                    download.failed = runCatching {
                        directory.mkdirs()
                        download.file.appendBytes(Base64.getDecoder().decode(data))
                    }.isFailure
                }
            }
            message.optBoolean("end") -> {
                // An empty Blob sends no chunk.
                val download = receiving.remove(id) ?: Receiving(File(directory, UUID.randomUUID().toString()))
                val url = message.getString("url")
                // A Blob without a type reports "".
                val type = Intent.normalizeMimeType(message.getString("type")).takeUnless { it.isNullOrEmpty() }
                    ?: "application/octet-stream"
                val name = message.getString("name").ifEmpty { URLUtil.guessFileName(url, null, type) }
                staging.execute {
                    if (!download.failed) {
                        download.failed = runCatching {
                            directory.mkdirs()
                            download.file.createNewFile()
                        }.isFailure
                    }
                    if (download.failed) download.file.delete()
                    activity.runOnUiThread {
                        if (download.failed) {
                            toast("Unable to read the download")
                        } else if (activity.isDestroyed) {
                            staging.execute { download.file.delete() }
                        } else {
                            queue.addLast(Staged(download.file, name, type))
                            next()
                        }
                    }
                }
            }
            else -> {
                receiving.remove(id)?.let { download -> staging.execute { download.file.delete() } }
                toast("Unable to read the download")
            }
        }
    }

    private fun next() {
        if (awaiting != null) return
        val download = queue.removeFirstOrNull() ?: return
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(download.type)
            .putExtra(Intent.EXTRA_TITLE, download.name)
        awaiting = download.file
        try {
            save.launch(intent)
        } catch (_: ActivityNotFoundException) {
            awaiting = null
            staging.execute { download.file.delete() }
            toast("No app can save this download")
            next()
        }
    }

    private fun toast(text: String) = Toast.makeText(activity, text, Toast.LENGTH_SHORT).show()

    private companion object {
        const val CHANNEL = "openseekDownloads"
        const val SAVE = "__openseekSaveDownload"

        const val STATE = "com.moonbit.openseek.downloads"
        const val AWAITING = "awaiting"

        /**
         * Staging-file work, in the order the UI thread queued it. Process-wide,
         * so a recreated activity's cleanup runs after its predecessor's writes.
         */
        val staging = Executors.newSingleThreadExecutor()

        /**
         * `click()` is wrapped because the page may activate an anchor it never
         * attaches, whose click event reaches no document listener. A remembered
         * read is dropped after a minute when no download follows, for instance
         * because a page listener cancelled the click.
         */
        val SCRIPT = """
            (() => {
              const reads = new Map();
              const remember = anchor => {
                if (anchor.protocol !== 'blob:' || !anchor.hasAttribute('download') || reads.has(anchor.href)) return;
                const url = anchor.href;
                reads.set(url, { name: anchor.download, blob: fetch(url).then(response => response.blob()) });
                setTimeout(() => reads.delete(url), 60000);
              };
              const click = HTMLElement.prototype.click;
              HTMLAnchorElement.prototype.click = function () {
                remember(this);
                return click.call(this);
              };
              addEventListener('click', event => {
                const anchor = event.target instanceof Element ? event.target.closest('a[download]') : null;
                if (anchor) remember(anchor);
              }, true);
              const CHUNK = 768 * 1024;
              const encode = blob => new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result.slice(reader.result.indexOf(',') + 1));
                reader.onerror = () => reject(reader.error);
                reader.readAsDataURL(blob);
              });
              Object.defineProperty(window, '$SAVE', {
                value: url => {
                  const read = reads.get(url) ?? { name: '', blob: fetch(url).then(response => response.blob()) };
                  reads.delete(url);
                  const id = crypto.randomUUID();
                  const post = message => $CHANNEL.postMessage(JSON.stringify({ id, ...message }));
                  read.blob
                    .then(async blob => {
                      for (let start = 0; start < blob.size; start += CHUNK) {
                        post({ data: await encode(blob.slice(start, start + CHUNK)) });
                      }
                      post({ end: true, url, name: read.name, type: blob.type });
                    })
                    .catch(() => post({ error: true }));
                },
              });
            })();
        """.trimIndent()
    }
}
