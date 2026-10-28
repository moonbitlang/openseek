package com.moonbit.openseek

import java.net.URI

/**
 * Native trust and asset boundaries. The only frontend routes known here are
 * the document paths openseek-api also serves; everything else stays the
 * frontend's own.
 */
internal object ConsoleOrigin {
    const val HOST = "seekmoon.moonbitlang.com"
    const val ORIGIN = "https://$HOST"
    const val ASSET_PATH = "/console/android/"
    const val ENTRY_URL = "${ORIGIN}${ASSET_PATH}index.html"

    /** The shared frontend's resources, which index.html names root-absolutely. */
    const val FRONTEND_PATH = "/assets/"

    /**
     * Pathnames the frontend navigates to as documents. openseek-api answers
     * them with its published frontend; the APK answers them with its own, so a
     * reload or a device switch keeps the packaged frontend.
     */
    fun servesDocument(path: String?): Boolean =
        path != null && (path == "/cloud" || path.startsWith("/cloud/") || path.startsWith("/device/"))

    fun contains(raw: String?): Boolean = runCatching {
        val uri = URI(requireNotNull(raw))
        uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals(HOST, ignoreCase = true) &&
            (uri.port == -1 || uri.port == 443) && uri.rawUserInfo == null
    }.getOrDefault(false)
}
