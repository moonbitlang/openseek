package com.moonbit.openseek

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.browser.auth.AuthTabIntent
import androidx.core.net.toUri
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Keeps the browser flow separate from the conversation WebView and its Back stack. */
class SignInActivity : ComponentActivity() {
    private var flow: BrowserSignIn? = null
    @Volatile private var outcome: Result<String>? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val browser = AuthTabIntent.registerActivityResultLauncher(this) { result ->
        val uri = result.resultUri
        if (result.resultCode == AuthTabIntent.RESULT_OK && uri != null &&
            flow?.acceptsReturn(uri.toString()) == true) {
            deliver()
        } else if (outcome != null) {
            // Older browsers return CANCELED when their fallback Custom Tab closes.
            deliver()
        } else {
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = "Complete sign-in in your browser."
            setPadding(32, 64, 32, 32)
        })
        if (savedInstanceState != null || intent.data != null) {
            // The process no longer owns the old loopback listener/verifier.
            fail("Sign-in was interrupted. Please try again.")
            return
        }
        executor.execute {
            try {
                val pending = BrowserSignIn(MainActivity.ORIGIN, packageName)
                flow = pending
                runOnUiThread {
                    if (!isFinishing) {
                        try {
                            AuthTabIntent.Builder().build().launch(browser, pending.startUri.toUri(), packageName)
                        } catch (_: ActivityNotFoundException) {
                            fail("Install or enable a browser to sign in.")
                        }
                    }
                }
                pending.receive(::exchange) { result, returning ->
                    outcome = result
                    // A callback response redirects the Auth Tab first. Keep this
                    // activity alive until that redirect delivers its result.
                    if (!returning) runOnUiThread {
                        if (!isFinishing) fail(result.exceptionOrNull()?.message ?: "Sign-in failed.")
                    }
                }
            } catch (_: Exception) {
                runOnUiThread { if (!isFinishing) fail("Unable to start sign-in. Please try again.") }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = intent.data ?: return
        if (flow?.acceptsReturn(uri.toString()) == true) deliver()
    }

    private fun exchange(code: String, verifier: String): String {
        val connection = URL("${MainActivity.ORIGIN}/v2/auth/account/exchange").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject().put("code", code).put("code_verifier", verifier).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            check(connection.responseCode == 200) { "Sign-in answered HTTP ${connection.responseCode}. Please try again." }
            val account = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val user = account.getJSONObject("user")
            require(account.getString("token").isNotEmpty() && user.getString("user_id").isNotEmpty())
            user.getString("login")
            user.getString("avatar_url")
            return account.toString()
        } finally { connection.disconnect() }
    }

    private fun deliver() {
        val result = outcome ?: return
        result.fold(
            onSuccess = { setResult(Activity.RESULT_OK, Intent().putExtra("account", it)); finish() },
            onFailure = { fail(it.message ?: "Sign-in failed.") },
        )
    }

    private fun fail(message: String) {
        setResult(Activity.RESULT_FIRST_USER, Intent().putExtra("error", message))
        finish()
    }

    override fun onDestroy() {
        flow?.close()
        executor.shutdownNow()
        super.onDestroy()
    }
}
