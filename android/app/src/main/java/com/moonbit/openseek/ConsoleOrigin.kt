package com.moonbit.openseek

import java.net.URI

/** Native trust and asset boundaries, independent of frontend routes. */
internal object ConsoleOrigin {
    const val HOST = "seekmoon.moonbitlang.com"
    const val ORIGIN = "https://$HOST"
    const val ASSET_PATH = "/console/android/"
    const val ENTRY_URL = "${ORIGIN}${ASSET_PATH}index.html"

    fun contains(raw: String?): Boolean = runCatching {
        val uri = URI(requireNotNull(raw))
        uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals(HOST, ignoreCase = true) &&
            (uri.port == -1 || uri.port == 443) && uri.rawUserInfo == null
    }.getOrDefault(false)
}
