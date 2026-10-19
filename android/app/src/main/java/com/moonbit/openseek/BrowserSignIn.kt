package com.moonbit.openseek

import java.io.Closeable
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets.UTF_8
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** The same S256 account flow used by Desktop; listens only on loopback. */
internal class BrowserSignIn(
    private val origin: String,
    private val returnScheme: String,
    private val timeoutMs: Int = 300_000,
) : Closeable {
    private val listener = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
    private val state = randomHex(16)
    private val verifier = randomHex(32)
    val returnUri: String = "$returnScheme://oauth/complete?state=$state"
    val startUri: String = "$origin/v2/auth/account/start?state=$state&code_challenge=" +
        Base64.getUrlEncoder().withoutPadding().encodeToString(
            MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(UTF_8))
        ) + "&code_challenge_method=S256&port=${listener.localPort}"

    fun acceptsReturn(raw: String?): Boolean = runCatching {
        val uri = URI(requireNotNull(raw))
        uri.scheme == returnScheme && uri.host == "oauth" &&
            uri.path == "/complete" && query(uri)["state"] == state
    }.getOrDefault(false)

    /** Complete is called before redirecting the browser back into the app. */
    fun receive(exchange: (String, String) -> String, complete: (Result<String>, Boolean) -> Unit) {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000L
        try {
            while (!listener.isClosed) {
                val remaining = ((deadline - System.nanoTime()) / 1_000_000).toInt()
                if (remaining <= 0) throw SocketTimeoutException()
                listener.soTimeout = remaining
                listener.accept().use { socket ->
                    socket.soTimeout = minOf(3000, remaining)
                    val line = try {
                        buildString {
                            val input = socket.getInputStream()
                            while (length < 8192) {
                                val byte = input.read()
                                if (byte == -1 || byte == 10) break
                                append(byte.toChar())
                            }
                        }.trimEnd('\r')
                    } catch (_: java.io.IOException) {
                        // A stray or stalled connection cannot cancel the login.
                        return@use
                    }
                    val parts = line.split(' ')
                    val uri = runCatching { URI(parts.getOrNull(1) ?: "") }.getOrNull()
                    val params = uri?.let { runCatching { query(it) }.getOrNull() }
                    val code = params?.get("code")?.takeIf { it.isNotEmpty() }
                    val error = params?.get("error")
                    if (parts.firstOrNull() != "GET" || uri?.path != "/cb" ||
                        params?.get("state") != state || (code == null && error == null)) {
                        runCatching {
                            socket.getOutputStream().write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(UTF_8))
                        }
                        return@use
                    }
                    val result = if (error != null) Result.failure(IllegalStateException("Sign-in was declined."))
                        else runCatching { exchange(requireNotNull(code), verifier) }
                    complete(result, true)
                    // The browser carries only a state-bound completion signal; the
                    // account token stays on the native HTTPS exchange and WebView.
                    runCatching {
                        socket.getOutputStream().write(("HTTP/1.1 303 See Other\r\nLocation: $returnUri\r\n" +
                            "Cache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").toByteArray(UTF_8))
                    }
                    return
                }
            }
        } catch (_: SocketTimeoutException) {
            complete(Result.failure(IllegalStateException("Sign-in timed out. Please try again.")), false)
        } catch (error: Exception) {
            if (!listener.isClosed) complete(Result.failure(error), false)
        } finally {
            close()
        }
    }

    override fun close() { listener.close() }

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
