# OpenSeek Connect for Android

Remote conversations through Connect. Kotlin hosts the shared MoonBit/Rabbita
frontend; conversations and commands run on the selected computer.

## Build

Requires Node, MoonBit, JDK 17+, Android SDK platform 36 and build tools.
Set ANDROID_HOME and JAVA_HOME for your installation, then run:

```sh
node android/build.mjs
```

APK: `android/app/build/outputs/apk/debug/app-debug.apk`

```sh
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.moonbit.openseek.connect.debug/com.moonbit.openseek.MainActivity
```

This is a debug-signed Android 8+ build, not a store release.

## Use

Enable Remote access in the desktop app, sign into the same GitHub account on
Android, select an online computer, then open or create a conversation.
“Choose a device” in the sidebar returns to the device list. Offline devices
are shown but cannot be opened. Refresh retries account/device failures.
Packaged development desktop builds start signed out on each launch; sign in
through Remote access before choosing that device on Android.

The existing frontend owns streaming, approvals, stop, conversation history and
WebSocket reconnection. Android owns keyboard/system-bar insets, file selection,
Back and WebView lifecycle. Files/editor/terminal entry buttons are hidden in this
first conversation-focused build. Switching device reloads the page; send or
save any draft first. No notification/background-service guarantee is provided.

## Authentication and assets

WebViewAssetLoader reserves `https://seekmoon.moonbitlang.com/console/android/`
for the APK bundle. The real Connect HTTP/WebSocket routes use that origin and
its session cookie. Login stays in WebView's cookie jar; native browser OAuth
would require a separate account-session handoff, not a device token exchange.
The exact bundled entry is reloaded directly after OAuth redirects because
WebView does not intercept subsequent resource URLs in a redirect chain.

There is no native JavaScript command bridge. Cleartext, mixed content and file
URL access are disabled; backup is disabled and inspection is debug-only.

## Validation

After `npm ci --prefix desktop/e2e` and building the APK:

```sh
cd desktop/e2e
OPENSEEK_DESKTOP_BROWSER_BASE_URL=http://127.0.0.1:52841 npx playwright test android_connect.spec.js console_http.spec.js session_message_approval.spec.js
```

On a test emulator with the Connect debug APK running:

```sh
ANDROID_SERIAL=emulator-5580 node android/smoke.mjs
```

The Android smoke uses demo account/host responses, verifies real keyboard
insets, Back, sending/stopping and the HTTP 302 return to bundled assets, then
reloads the real entry page. It preserves application data and credentials.
These fixture checks do not establish an end-to-end run on your real computer;
that requires signing into GitHub and choosing your online device.
