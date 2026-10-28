package com.moonbit.openseek

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewAssetLoader
import org.json.JSONObject

/** Remote client only. No native command bridge or local agent runtime. */
class MainActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private var fileResult: ValueCallback<Array<Uri>>? = null
    private val signIn = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val account = result.data?.getStringExtra("account")
        if (result.resultCode == Activity.RESULT_OK && account != null && ConsoleOrigin.contains(webView.url)) {
            // The frontend owns its current destination. Refresh it after updating
            // the shared account store; never parse or rebuild an application URL.
            // Tokens never appear in a navigation URL or native link.
            webView.evaluateJavascript(
                "localStorage.setItem('seekmoon.account.v1', ${JSONObject.quote(account)});" +
                    "location.reload();", null
            )
        } else {
            // The frontend marked a sign-in as pending before its navigation,
            // which this activity took over. Reload it so Sign in works again
            // after a cancellation, denial or failed exchange.
            if (ConsoleOrigin.contains(webView.url)) webView.reload()
            result.data?.getStringExtra("error")?.let { message ->
                AlertDialog.Builder(this).setTitle("Unable to sign in").setMessage(message)
                    .setPositiveButton("OK", null).show()
            }
        }
    }
    private val picker = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        fileResult?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(it.resultCode, it.data))
        fileResult = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        webView = WebView(this)
        val frame = FrameLayout(this)
        frame.addView(webView, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        // The keyboard arrives as an ime() inset: edge-to-edge delivers it on
        // Android 11+, and the manifest's adjustResize delivers it on 8–10.
        ViewCompat.setOnApplyWindowInsetsListener(frame) { view, insets ->
            val visible = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or
                    WindowInsetsCompat.Type.ime()
            )
            view.setPadding(visible.left, visible.top, visible.right, visible.bottom)
            insets
        }
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        // Reserve this path for the APK's own frontend. API calls retain the
        // real HTTPS origin, its cookies and the shared account-token and Connect-ticket protocol.
        // The frontend's own document routes (/cloud, /device/...) are answered
        // with the same bundled document below, never fetched from the server.
        // The bundle keeps the frontend's /assets/ resources in the APK's assets/
        // directory, so they too come from the APK rather than the server.
        val bundled = WebViewAssetLoader.AssetsPathHandler(this)
        val assets = WebViewAssetLoader.Builder()
            .setDomain(ConsoleOrigin.HOST)
            .addPathHandler(ConsoleOrigin.ASSET_PATH, bundled)
            .addPathHandler(ConsoleOrigin.FRONTEND_PATH) { path -> bundled.handle("assets/$path") }
            .build()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val url = request.url
                if (request.isForMainFrame && request.method == "GET" &&
                    ConsoleOrigin.contains(url.toString()) && ConsoleOrigin.servesDocument(url.path)) {
                    return WebResourceResponse("text/html", "utf-8", this@MainActivity.assets.open("index.html"))
                }
                return assets.shouldInterceptRequest(url)
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                if (ConsoleOrigin.contains(uri.toString())) {
                    if (request.isForMainFrame && uri.path == "/v2/auth/login" && ConsoleOrigin.contains(view.url)) {
                        signIn.launch(Intent(this@MainActivity, SignInActivity::class.java))
                        return true
                    }
                    return false
                }
                if (request.isForMainFrame && request.hasGesture() && uri.scheme in setOf("https", "http", "mailto")) {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                    } catch (_: ActivityNotFoundException) {
                        Toast.makeText(this@MainActivity, "No app can open this link", Toast.LENGTH_SHORT).show()
                    }
                }
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                CookieManager.getInstance().flush()
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame && !isFinishing) {
                    showLoadError(view, "The server answered HTTP ${response.statusCode}.")
                }
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame && !isFinishing) {
                    showLoadError(view, error.description.toString())
                }
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams
            ): Boolean {
                // Only documents on the application origin may request attachments.
                if (!ConsoleOrigin.contains(view.url)) return false
                fileResult?.onReceiveValue(null)
                fileResult = callback
                try {
                    picker.launch(params.createIntent())
                } catch (_: ActivityNotFoundException) {
                    fileResult?.onReceiveValue(null)
                    fileResult = null
                }
                return true
            }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (ConsoleOrigin.contains(webView.url)) {
                    webView.evaluateJavascript(CLOSE_OVERLAY) { handled ->
                        if (handled != "true") navigateBack()
                    }
                } else navigateBack()
            }
        })
        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(ConsoleOrigin.ENTRY_URL)
        }
    }

    private fun showLoadError(view: WebView, message: String) {
        AlertDialog.Builder(this)
            .setTitle("Unable to connect")
            .setMessage(message)
            .setPositiveButton("Retry") { _, _ -> view.reload() }
            .setNegativeButton("Home") { _, _ -> view.loadUrl(ConsoleOrigin.ENTRY_URL) }
            .show()
    }

    private fun navigateBack() {
        if (webView.canGoBack()) webView.goBack() else moveTaskToBack(true)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onPause() {
        CookieManager.getInstance().flush()
        super.onPause()
    }

    override fun onDestroy() {
        fileResult?.onReceiveValue(null)
        webView.destroy()
        super.onDestroy()
    }

    companion object {
        private val CLOSE_OVERLAY = """
            (() => {
                const popover = [...document.querySelectorAll(':popover-open')].pop();
                if (popover) {
                    // A component that owns the popover's open state closes it
                    // on Escape from its trigger or contents; hiding the element
                    // alone would leave that state open.
                    const focus = document.activeElement;
                    const owned = focus && (popover.contains(focus) ||
                        (popover.id && focus.getAttribute('aria-controls') === popover.id));
                    const escape = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
                    if (!owned || focus.dispatchEvent(escape)) popover.hidePopover();
                    return true;
                }
                // Action menus and the composer's Git menu close on Escape from
                // inside them, which restores focus, or on a click outside them.
                const menu = [...document.querySelectorAll('[data-action-menu-surface], .composer-git-menu')].pop();
                if (menu) {
                    const focus = document.activeElement;
                    const escape = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
                    if (!(focus && menu.contains(focus)) || focus.dispatchEvent(escape)) document.body.click();
                    return true;
                }
                // The topmost modal next, as Escape would: a native dialog's
                // cancel handler or a confirmation's backdrop dismisses it.
                const dialog = [...document.querySelectorAll('dialog[open]')].pop();
                if (dialog) { dialog.dispatchEvent(new Event('cancel', { cancelable: true })); return true; }
                const modal = [...document.querySelectorAll('.modal-backdrop')].pop();
                if (modal) { modal.click(); return true; }
                const drawer = document.querySelector('.sidebar-backdrop.open');
                if (drawer) { drawer.click(); return true; }
                const panel = document.querySelector('.content.panel-open .right-panel-toggle');
                if (panel) { panel.click(); return true; }
                const back = document.querySelector('.management-page-return');
                if (back) { back.click(); return true; }
                return false;
            })()
        """.trimIndent()
    }
}
