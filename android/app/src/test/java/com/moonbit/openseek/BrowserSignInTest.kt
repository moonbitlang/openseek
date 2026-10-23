package com.moonbit.openseek

import org.junit.Assert.*
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

class BrowserSignInTest {
    private fun params(uri: String) = URI(uri).rawQuery.split('&').associate {
        val pair = it.split('=', limit = 2)
        pair[0] to pair[1]
    }

    private fun get(uri: String): HttpURLConnection = (URL(uri).openConnection() as HttpURLConnection).apply {
        instanceFollowRedirects = false
        connectTimeout = 1000
        readTimeout = 2000
    }

    @Test fun callbackValidatesStateAndExchangesWithTheOriginalVerifier() {
        BrowserSignIn("https://relay.test", "com.example.app", 3000).use { flow ->
            val query = params(flow.startUri)
            val completed = CompletableFuture<Result<String>>()
            val worker = CompletableFuture.runAsync {
                flow.receive({ code, verifier ->
                    assertEquals("once", code)
                    val challenge = Base64.getUrlEncoder().withoutPadding().encodeToString(
                        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
                    )
                    assertEquals(query["code_challenge"], challenge)
                    "private-account-result"
                }, { result, returning -> assertTrue(returning); completed.complete(result) })
            }
            val callback = "http://127.0.0.1:${query["port"]}/cb"
            get("$callback?state=forged&code=once").also {
                assertEquals(404, it.responseCode); it.disconnect()
            }
            assertFalse(completed.isDone)
            get("$callback?state=${query["state"]}&code=once").also {
                assertEquals(303, it.responseCode)
                assertEquals(flow.returnUri, it.getHeaderField("Location"))
                assertFalse(it.getHeaderField("Location").contains("private-account-result"))
                it.disconnect()
            }
            assertEquals("private-account-result", completed.get(2, TimeUnit.SECONDS).getOrThrow())
            worker.get(2, TimeUnit.SECONDS)
            assertTrue(flow.acceptsReturn(flow.returnUri))
            assertFalse(flow.acceptsReturn("com.example.app://oauth/complete?state=forged"))
            assertFalse(flow.acceptsReturn(flow.returnUri.replace("/complete", "/other")))
            assertFalse(flow.acceptsReturn("com.example.app://oauth/complete?state=%bad%"))
            assertFalse(flow.acceptsReturn(null))
        }
    }

    @Test fun denialDoesNotExchangeAndReturnsToTheApp() {
        BrowserSignIn("https://relay.test", "com.example.app", 3000).use { flow ->
            val query = params(flow.startUri)
            val completed = CompletableFuture<Result<String>>()
            val worker = CompletableFuture.runAsync {
                flow.receive({ _, _ -> throw AssertionError("Denied login must not exchange") }, { result, returning -> assertTrue(returning); completed.complete(result) })
            }
            get("http://127.0.0.1:${query["port"]}/cb?state=${query["state"]}&error=access_denied").also {
                assertEquals(303, it.responseCode); it.disconnect()
            }
            assertTrue(completed.get(2, TimeUnit.SECONDS).isFailure)
            worker.get(2, TimeUnit.SECONDS)
        }
    }

    @Test fun exchangeFailureStillClosesTheBrowserRoundTrip() {
        BrowserSignIn("https://relay.test", "com.example.app", 3000).use { flow ->
            val query = params(flow.startUri)
            val completed = CompletableFuture<Result<String>>()
            val worker = CompletableFuture.runAsync {
                flow.receive({ _, _ -> error("Fixture exchange rejected") }, { result, returning -> assertTrue(returning); completed.complete(result) })
            }
            get("http://127.0.0.1:${query["port"]}/cb?state=${query["state"]}&code=once").also {
                assertEquals(303, it.responseCode); it.disconnect()
            }
            assertTrue(completed.get(2, TimeUnit.SECONDS).isFailure)
            worker.get(2, TimeUnit.SECONDS)
        }
    }

    @Test fun cancellationStopsTheListenerWithoutDeliveringAnAccount() {
        val flow = BrowserSignIn("https://relay.test", "com.example.app", 3000)
        val completed = CompletableFuture<Result<String>>()
        val worker = CompletableFuture.runAsync {
            flow.receive({ _, _ -> error("Cancelled login must not exchange") }, { result, returning -> assertTrue(returning); completed.complete(result) })
        }
        flow.close()
        worker.get(2, TimeUnit.SECONDS)
        assertFalse(completed.isDone)
    }

    @Test fun timeoutClosesTheListenerAndReportsFailure() {
        BrowserSignIn("https://relay.test", "com.example.app", 50).use { flow ->
            var result: Result<String>? = null
            flow.receive({ _, _ -> throw AssertionError("No callback") }, { value, returning -> assertFalse(returning); result = value })
            assertTrue(requireNotNull(result).isFailure)
            assertTrue(requireNotNull(result).exceptionOrNull()?.message?.contains("timed out") == true)
        }
    }
}
