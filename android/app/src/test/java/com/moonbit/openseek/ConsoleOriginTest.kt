package com.moonbit.openseek

import org.junit.Assert.*
import org.junit.Test

class ConsoleOriginTest {
    @Test fun applicationOwnershipDoesNotDependOnRoutesOrQueryParameters() {
        for (path in listOf(
            "/console/android/index.html",
            "/",
            "/an-arbitrary-future-route?key=value#section",
            "/device/device-a/chat/session/session-1?key=value#section",
        )) {
            assertTrue(path, ConsoleOrigin.contains(ConsoleOrigin.ORIGIN + path))
        }
        assertTrue(ConsoleOrigin.contains("https://${ConsoleOrigin.HOST}:443/another-route"))
        assertTrue(ConsoleOrigin.contains("HTTPS://SEEKMOON.MOONBITLANG.COM/another-route"))
    }

    @Test fun onlyTheApplicationHttpsOriginIsAccepted() {
        for (url in listOf(
            null,
            "not a URL",
            "/console/android/index.html",
            "http://${ConsoleOrigin.HOST}/",
            "https://${ConsoleOrigin.HOST}:444/",
            "https://${ConsoleOrigin.HOST}.example/",
            "https://${ConsoleOrigin.HOST}@example.com/",
            "https://example.com@${ConsoleOrigin.HOST}/",
            "javascript:alert(1)",
            "file:///console/android/index.html",
        )) {
            assertFalse(url, ConsoleOrigin.contains(url))
        }
    }
}
