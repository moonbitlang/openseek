# OpenSeek Connect for Android

Remote conversations through Connect. Kotlin hosts the shared MoonBit/Rabbita
frontend; Connect conversations and commands run on the selected computer.
The shared Chat tab also provides Cloud conversations without a connected device.

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

The app opens Chat. Sign in with GitHub to create a Cloud conversation without
connecting a computer. Login opens the system browser's Auth Tab (or Custom Tab
fallback), reuses its GitHub session and returns to the app.

For Connect, enable Remote access in the desktop app and sign in with the same
GitHub account. Use “Choose a device”, select an online computer, then open or
create a conversation. “Choose a device” in the sidebar returns to the device list. Offline devices
are shown but cannot be opened. Refresh retries account/device failures.
Packaged development desktop builds start signed out on each launch; sign in
through Remote access before choosing that device on Android.

The existing frontend owns streaming, approvals, stop, conversation history and
WebSocket reconnection. A dropped connection shows one inline reconnecting
notice, preserves the draft, and disables sending until the host returns.
Background inventory reads do not add duplicate connection-loss toasts; host
rejections remain visible. Android owns keyboard/system-bar insets, file selection,
Back and WebView lifecycle. Files/editor/terminal entry buttons are hidden in this
first conversation-focused build. Switching device reloads the page; send or
save any draft first. No notification/background-service guarantee is provided.

## Authentication and assets

WebViewAssetLoader reserves `https://seekmoon.moonbitlang.com/console/android/`
for the APK bundle. The real Connect HTTP/WebSocket routes use that origin and
the shared v2 account token; WebSocket connections use single-use Connect tickets.
Browser login uses the existing `/v2/auth/account/start` and account exchange
with S256 PKCE and a state-checked, short-lived loopback listener. The browser
returns a completion signal through an app link; the account token never enters
a URL. Android transfers the exchanged session into the bundled WebView's
existing account store. Cancellation closes the listener; an interrupted process
requires a fresh login attempt. WebView cookies and browser cookies stay separate.

There is no native JavaScript command bridge. Cleartext, mixed content and file
URL access are disabled; backup is disabled and inspection is debug-only.

## Validation

Shared mobile layout, Chat/Connect entry and offline behavior are browser
features. Their tests live under `desktop/e2e/tests` and require no Android
build; see [Mobile browser client](../desktop/MOBILE_BROWSER.md). Android adds
only native authentication, insets/lifecycle, Back, file picking and packaging.
`conversation.css` hides panel buttons for this first conversation-only client;
all responsive styling comes from the shared browser bundle.

After building the APK:

```sh
./android/gradlew -p android testDebugUnitTest lintDebug
```

The native tests exercise the actual loopback listener, PKCE verifier binding,
stray callback rejection, denial, exchange failure, cancellation and timeout.
On a test emulator with the Connect debug APK running:

```sh
ANDROID_SERIAL=emulator-5580 node android/smoke.mjs
```

The Android smoke uses demo account/host responses, verifies real keyboard
insets, Back and sending/stopping, then
reloads the real entry page. It preserves application data and credentials.
These fixture checks do not establish an end-to-end run on your real computer;
that requires signing into GitHub and choosing your online device.
