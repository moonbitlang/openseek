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
    private lateinit var status: TextView

    /** Set once the code is being redeemed; later returns change nothing. */
    private var redeeming = false
    private val executor = Executors.newSingleThreadExecutor()
    private val browser = AuthTabIntent.registerActivityResultLauncher(this) { result ->
        val answer = if (result.resultCode == AuthTabIntent.RESULT_OK) flow?.answer(result.resultUri?.toString()) else null
        if (redeeming) {
            // The fallback Custom Tab closes after its return reached onNewIntent,
            // which runs first: this result waits for the activity's start.
        } else if (answer != null) {
            deliver(answer)
        } else {
            setResult(Activity.RESULT_CANCELED)
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = TextView(this).apply {
            text = "Complete sign-in in your browser."
            setPadding(32, 64, 32, 32)
        }
        setContentView(status)
        if (savedInstanceState != null || intent.data != null) {
            // The process no longer holds the old flow's state and verifier.
            fail("Sign-in was interrupted. Please try again.")
            return
        }
        val pending = BrowserSignIn(ConsoleOrigin.ORIGIN, packageName)
        flow = pending
        try {
            AuthTabIntent.Builder().build().launch(browser, pending.startUri.toUri(), packageName)
        } catch (_: ActivityNotFoundException) {
            fail("Install or enable a browser to sign in.")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        flow?.answer(intent.data?.toString())?.let(::deliver)
    }

    private fun exchange(code: String, verifier: String): String {
        val connection = URL("${ConsoleOrigin.ORIGIN}/v2/auth/account/exchange").openConnection() as HttpURLConnection
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

    /** Runs once the browser has returned, with this activity in the foreground. */
    private fun deliver(answer: Result<String>) {
        if (redeeming) return
        val pending = flow ?: return
        answer.fold(
            onSuccess = { code ->
                redeeming = true
                status.text = "Signing in…"
                executor.execute {
                    val account = runCatching { exchange(code, pending.verifier) }
                    runOnUiThread {
                        if (!isFinishing) account.fold(
                            onSuccess = { setResult(Activity.RESULT_OK, Intent().putExtra("account", it)); finish() },
                            onFailure = { fail(it.message ?: "Sign-in failed.") },
                        )
                    }
                }
            },
            onFailure = { fail(it.message ?: "Sign-in failed.") },
        )
    }

    private fun fail(message: String) {
        setResult(Activity.RESULT_FIRST_USER, Intent().putExtra("error", message))
        finish()
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
