package com.moonbit.openseek

import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.security.MessageDigest
import java.util.Base64

class BrowserSignInTest {
    private fun params(uri: String) = URI(uri).rawQuery.split('&').associate {
        val pair = it.split('=', limit = 2)
        pair[0] to pair[1]
    }

    @Test fun startReturnsToTheAppSchemeWithTheVerifiersChallenge() {
        val flow = BrowserSignIn("https://relay.test", "com.example.app")
        assertTrue(flow.startUri.startsWith("https://relay.test/v2/auth/account/start?"))
        val query = params(flow.startUri)
        assertEquals("com.example.app", query["scheme"])
        assertFalse(query.containsKey("port"))
        assertEquals("S256", query["code_challenge_method"])
        val challenge = Base64.getUrlEncoder().withoutPadding().encodeToString(
            MessageDigest.getInstance("SHA-256").digest(flow.verifier.toByteArray())
        )
        assertEquals(challenge, query["code_challenge"])
    }

    @Test fun answerAcceptsOnlyThisFlowsReturn() {
        val flow = BrowserSignIn("https://relay.test", "com.example.app")
        val state = params(flow.startUri)["state"]
        val complete = "com.example.app://oauth/complete"
        assertEquals("ac_once", flow.answer("$complete?code=ac_once&state=$state")?.getOrThrow())
        assertTrue(flow.answer("$complete?error=access_denied&state=$state")!!.isFailure)
        assertNull(flow.answer("$complete?code=ac_once&state=forged"))
        assertNull(flow.answer("$complete?state=$state"))
        assertNull(flow.answer("com.evil.app://oauth/complete?code=ac_once&state=$state"))
        assertNull(flow.answer("com.example.app://oauth/other?code=ac_once&state=$state"))
        assertNull(flow.answer("$complete?code=%bad%&state=$state"))
        assertNull(flow.answer(null))
    }
}
