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

This builds a debug-signed Android 8+ APK. CI runs the same build, lint and
native tests on pull requests and uploads the debug APK as an Actions artifact.
The debug app has a separate application ID and can coexist with the release.

## Release and homepage downloads

The existing `Desktop release` workflow builds Android on `main` alongside
macOS, Windows and Browser. It reuses that run's Browser archive, stamps the
same version into the APK, then uploads `SeekMoon-android.apk` to both OSS and
S3. The publisher verifies size and SHA-256 before adding `platforms.android`
to the API-owned release manifest. The homepage reads that manifest; the
Android download card appears once a release includes the APK.

Configure these repository Actions secrets before enabling the first release:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded release keystore.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_ALIAS`: signing key alias.
- `ANDROID_KEY_PASSWORD`: signing key password.

Keep a private backup of the keystore and passwords outside the repository.
All future updates must use the same signing key. Signing secrets are read only
by the main-only release build, never by pull-request checks. Missing secrets
fail the release before publication; the workflow never substitutes a debug key.
The temporary runner keystore is removed when the build step exits.

For a local signed build, export the matching environment variables, then run:

```sh
export OPENSEEK_ANDROID_KEYSTORE_PATH=/absolute/path/to/release.jks
export OPENSEEK_ANDROID_KEY_ALIAS=release
# Supply OPENSEEK_ANDROID_KEYSTORE_PASSWORD and OPENSEEK_ANDROID_KEY_PASSWORD
# privately in your environment; do not commit them or put them in commands.
node android/build.mjs --release
```

Output: `desktop/dist/SeekMoon-android.apk`. Without `--browser-bundle`, the
script builds the frontend from the checkout. CI passes
`--browser-bundle desktop/dist/SeekMoon.browser.tar.gz` from the same release.
The APK's version defaults to `desktop/moon.mod`; `-PreleaseVersion=X.Y.Z`
overrides it for a direct Gradle build. Versions follow the release workflow's
`major.minor.patch` range (major <= 9999, minor/patch <= 99), with a monotonic
Android `versionCode` of `major * 10000 + minor * 100 + patch + 1`.
Older releases predating Android remain valid rollback targets.

The launcher icon uses the white rabbit paths from
`desktop/package/macos/appicon.svg` and the blue background (`#3B6EF5`) from
Desktop's packaged `AppIcon.icns` / `appicon.png`. Android applies its own
adaptive icon mask; Android 13+ also has a monochrome layer for themed icons.

## Use

The app loads the shared browser entry without selecting a view. The frontend
owns the initial page and saved sidebar preference. Sign in with GitHub to use
Cloud conversations without connecting a computer. Login opens the system
browser's Auth Tab (or Custom Tab fallback), reuses its GitHub session and
returns to the app.

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
a URL. Android transfers the exchanged session into the WebView's existing account
store and reloads the current document. It does not parse the login `return_to`
parameter, select Chat/Work or rebuild the frontend's current URL. Cancellation
closes the listener; an interrupted process requires a fresh login attempt. WebView cookies and browser cookies stay separate.

Native ownership checks use the HTTPS origin, not an application route. The
`/console/android/` mount identifies APK assets only; it does not determine
whether login, Back or file selection is available. CSR route parsing and history
belong to the frontend. After #2045 lands, verify deep-link refresh and asset
resolution with that frontend before claiming end-to-end CSR support.

There is no native JavaScript command bridge. Cleartext, mixed content and file
URL access are disabled; backup is disabled and inspection is debug-only.

## Validation

Shared mobile layout, Chat/Connect entry and offline behavior are browser
features. Their tests live under `desktop/e2e/tests` and require no Android
build; see [Mobile browser client](../desktop/MOBILE_BROWSER.md). Android adds
only native authentication, insets/lifecycle, Back, file picking and packaging.
`conversation.css` hides panel buttons for this first conversation-only client.
Its link uses the absolute APK asset path, so a frontend `<base>` or history
change cannot relocate it. Responsive styling comes from the shared bundle.

After building the APK:

```sh
./android/gradlew -p android testDebugUnitTest lintDebug
```

The native tests exercise the actual loopback listener, PKCE verifier binding,
stray callback rejection, denial, exchange failure, cancellation and timeout.
Origin tests cover arbitrary frontend paths and reject other origins.
On a test emulator with the Connect debug APK running:

```sh
ANDROID_SERIAL=emulator-5580 node android/smoke.mjs
```

The Android smoke uses demo account/host responses, verifies real keyboard
insets, Back and sending/stopping, then
reloads the real entry page. It preserves application data and credentials.
These fixture checks do not establish an end-to-end run on your real computer;
that requires signing into GitHub and choosing your online device.
