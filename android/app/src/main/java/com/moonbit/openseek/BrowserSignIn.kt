package com.moonbit.openseek

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets.UTF_8
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * The same S256 account flow used by Desktop, except that the browser returns
 * to the app's own scheme rather than a loopback port. Android freezes the
 * app's process while the browser covers it, and a frozen process cannot
 * answer a loopback redirect; the system delivers a scheme URL regardless.
 */
internal class BrowserSignIn(origin: String, private val returnScheme: String) {
    private val state = randomHex(16)

    /** Redeems the code [answer] returns, with this flow's challenge. */
    val verifier = randomHex(32)
    val startUri: String = "$origin/v2/auth/account/start?state=$state&code_challenge=" +
        Base64.getUrlEncoder().withoutPadding().encodeToString(
            MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(UTF_8))
        ) + "&code_challenge_method=S256&scheme=$returnScheme"

    /**
     * The browser's answer in the return URL [raw]: the authorization code, or
     * why there is none. Null when [raw] is not this flow's return, for
     * instance one carrying another flow's state.
     */
    fun answer(raw: String?): Result<String>? {
        val params = runCatching {
            val uri = URI(requireNotNull(raw))
            check(uri.scheme == returnScheme && uri.host == "oauth" && uri.path == "/complete")
            query(uri)
        }.getOrNull()
        if (params == null || params["state"] != state) return null
        val code = params["code"]?.takeIf { it.isNotEmpty() }
        return when {
            code != null -> Result.success(code)
            params.containsKey("error") -> Result.failure(IllegalStateException("Sign-in was declined."))
            else -> null
        }
    }

    companion object {
        private fun randomHex(bytes: Int): String = ByteArray(bytes).also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }

        private fun query(uri: URI): Map<String, String> = (uri.rawQuery ?: "").split('&')
            .filter { it.contains('=') }.associate {
                val (key, value) = it.split('=', limit = 2)
                URLDecoder.decode(key, "UTF-8") to URLDecoder.decode(value, "UTF-8")
            }
    }
}
