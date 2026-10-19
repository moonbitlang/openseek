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
import androidx.core.net.toUri
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewAssetLoader
import org.json.JSONObject

/** Remote client only. No native command bridge or local agent runtime. */
class MainActivity : ComponentActivity() {
    private lateinit var webView: WebView
    private var fileResult: ValueCallback<Array<Uri>>? = null
    private var loginReturnTo = HOME
    private val signIn = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val account = result.data?.getStringExtra("account")
        if (result.resultCode == Activity.RESULT_OK && account != null && isHome(webView.url)) {
            // Write the existing shared account format only into our bundled
            // origin. Tokens never appear in a navigation URL or native link.
            webView.evaluateJavascript(
                "localStorage.setItem('seekmoon.account.v1', ${JSONObject.quote(account)});" +
                    "location.replace(${JSONObject.quote(loginReturnTo)});", null
            )
        } else {
            webView.loadUrl(loginReturnTo)
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
        loginReturnTo = savedInstanceState?.getString("loginReturnTo") ?: HOME
        webView = WebView(this)
        val frame = FrameLayout(this)
        frame.addView(webView, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
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
        val assets = WebViewAssetLoader.Builder()
            .setDomain(HOST)
            .addPathHandler("/console/android/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                assets.shouldInterceptRequest(request.url)

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                if (uri.scheme == "https" && uri.host == HOST &&
                    (uri.port == -1 || uri.port == 443)) {
                    if (request.isForMainFrame && uri.path == "/v2/auth/login" && isHome(view.url)) {
                        val target = uri.getQueryParameter("return_to")
                        val destination = target?.let { "$ORIGIN$it" }
                        loginReturnTo = if (isHome(destination)) requireNotNull(destination) else HOME
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
                // Only the bundled console may request local attachments.
                if (!isHome(view.url)) return false
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
                if (isHome(webView.url)) {
                    webView.evaluateJavascript(CLOSE_OVERLAY) { handled ->
                        if (handled != "true") navigateBack()
                    }
                } else navigateBack()
            }
        })
        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(HOME)
        }
    }

    private fun showLoadError(view: WebView, message: String) {
        AlertDialog.Builder(this)
            .setTitle("Unable to connect")
            .setMessage(message)
            .setPositiveButton("Retry") { _, _ -> view.reload() }
            .setNegativeButton("Chat") { _, _ -> view.loadUrl(HOME) }
            .show()
    }

    private fun isHome(url: String?): Boolean {
        if (url == null) return false
        val uri = url.toUri()
        return uri.scheme == "https" && uri.host == HOST &&
            (uri.port == -1 || uri.port == 443) && uri.path == HOME_PATH
    }

    private fun navigateBack() {
        if (webView.canGoBack()) webView.goBack() else moveTaskToBack(true)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        outState.putString("loginReturnTo", loginReturnTo)
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
        private const val HOST = "seekmoon.moonbitlang.com"
        private const val HOME_PATH = "/console/android/index.html"
        internal const val ORIGIN = "https://$HOST"
        private const val HOME = "$ORIGIN$HOME_PATH?view=chat"
        private val CLOSE_OVERLAY = """
            (() => {
                const popover = document.querySelector(':popover-open');
                if (popover) { popover.hidePopover(); return true; }
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
