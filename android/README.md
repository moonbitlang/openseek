# SeekMoon for Android

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

## Self-update

Release builds update themselves from the same manifest as Desktop
(`https://seekmoon.moonbitlang.com/desktop/releases/latest.json`). Each
time the app comes to the foreground, at most once every six hours, it
compares the manifest's `version` with its own `versionName`. When
`platforms.android` names a newer APK, a dialog offers to update. The system
`DownloadManager` then fetches the APK into the app's external files
directory, showing progress in the notification shade and retrying across
network loss and process death. When the download completes while the app is
in the foreground, or on the next return to it, the app checks the SHA-256
and starts the installation. If no newer release exists, or the release has
no APK, the app shows nothing, and manifest failures only reach the log; a
failed download shows a message.

Installing goes through `PackageInstaller`. The first time, Android asks the
user to allow installs from SeekMoon (`REQUEST_INSTALL_PACKAGES`); the app
then continues the installation when it returns from Settings. Android shows
its own confirmation unless the device is on Android 12+ and this app
installed the current version itself (`UPDATE_PACKAGES_WITHOUT_USER_ACTION`).
If Android destroys the app while the user is in Settings, the pending
installation is restored from the saved state. Installing stops the running
app, and Android does not reopen it. Android rejects an APK signed with a
different key, which is why every release must keep the same keystore.
Debug builds (`.debug`) never check for updates.

## Frontend updates

The app runs the same frontend as browsers without a new APK. Each time it
comes to the foreground, at most once every 30 minutes, it reads which Browser
release openseek-api serves at `/cloud`
(`https://seekmoon.moonbitlang.com/browser/releases/current.json`). That may be
a Desktop release (`0.2.52`) or a console-only one (`browser-3.1`). These kinds
share no order, so the app follows whatever the server selects, rollbacks
included. When that release differs from the one the app runs, the app downloads
its archive (`/desktop/releases/v<release>/SeekMoon.browser.tar.gz`) in the
background, checks its gzip CRC, and extracts it into app-private storage,
leaving out the `.br`/`.gz` copies the server uses. The app runs that release
from the next time it creates its WebView (normally the next launch), so a page
never mixes two releases' files. A release the server selects that matches the
APK's own version switches back to the bundled frontend without a download.

Each Browser bundle declares the oldest APK whose shell it works with in
`android.json`, copied from [`frontend.json`](frontend.json) by
`desktop/package/build.mjs browser`. Raise `min_android_version` to the release
that ships a shell change when the frontend starts to depend on that change.
The app adopts a release only when its own version is at least that minimum; it
remembers a refused release and does not download it again, and keeps its
current frontend until the APK itself updates. Bundles without `android.json`
predate frontend updates and are never adopted. A new APK starts from its own
bundle again and deletes the releases downloaded for the previous one. Failures
only reach the log.

Debug builds keep the frontend of their checkout. Pass `-PfrontendUpdates`
to Gradle to follow the published one, and `-PreleaseVersion=X.Y.Z` to meet
the bundle's minimum.

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
for the app's frontend: the downloaded Browser release once one is ready (see
Frontend updates), otherwise the APK bundle. The real Connect HTTP/WebSocket routes use that origin and
the shared v2 account token; WebSocket connections use single-use Connect tickets.
Browser login uses the existing `/v2/auth/account/start` and account exchange
with S256 PKCE. Instead of a loopback port it passes the application ID as
`scheme`, so the browser returns the state-checked code to
`<application id>://oauth/complete`: Android freezes the app's process while
the user is away from it, and a frozen process cannot answer a loopback
redirect. The code is useless without the app's verifier, and the account token
never enters a URL. Android transfers the exchanged session into the WebView's existing account
store and reloads the current document. It does not parse the login `return_to`
parameter, select Chat/Work or rebuild the frontend's current URL. An interrupted process requires a fresh login attempt. WebView cookies and browser cookies stay separate.

Native ownership checks use the HTTPS origin, not an application route. The
`/console/android/` mount identifies APK assets only; it does not determine
whether login, Back or file selection is available. CSR route parsing and history
belong to the frontend. After #2045 lands, verify deep-link refresh and asset
resolution with that frontend before claiming end-to-end CSR support.

There is no native JavaScript command bridge. Cleartext, mixed content and file
URL access are disabled; backup is disabled and inspection is debug-only.

Back dispatches the frontend's cancelable `openseek-back` event on the document.
The frontend closes its topmost open layer (a menu, dialog, the drawer, a
management page) and cancels the event, as Escape does on a keyboard; Android
goes back in the WebView's history only when no layer closed. The shell knows
nothing of the frontend's layers or DOM (`desktop/frontend/dismiss/back.mbt`).

## Validation

Shared mobile layout, Chat/Connect entry and offline behavior are browser
features. Their tests live under `desktop/e2e/tests` and require no Android
build; see [Desktop end-to-end tests](../desktop/e2e/README.md). Android adds
only native authentication, insets/lifecycle, Back, file picking, downloads and
packaging. The shared frontend's `/assets/` resources are answered from the
APK or the downloaded release, never fetched per request. The APK adds no styling: which controls a phone or tablet shows is the
shared bundle's responsive layout, as in a mobile browser.

WebView cannot fetch a `blob:` download and drops the anchor's `download`
name. A document-start script on the application origin remembers each blob
anchor the page activates and reads it before the page revokes its URL; the
shell then offers Android's save dialog (`BlobDownloads.kt`).

After building the APK:

```sh
./android/gradlew -p android testDebugUnitTest lintDebug
```

The native tests cover the start URL's scheme and PKCE challenge, and the
return URL's state check, denial and rejection of other returns. The code is
redeemed only after the browser has returned to the app, since Android 15 and
later fail a backgrounded app's network requests.
Origin tests cover arbitrary frontend paths and reject other origins.
Frontend update tests cover the release pointer, the `android.json` minimum,
archive extraction (long paths, dropped copies, unsafe and truncated archives)
and switching releases only on the next WebView.
On a test emulator with the Connect debug APK running:

```sh
ANDROID_SERIAL=emulator-5580 node android/smoke.mjs
```

The Android smoke uses demo account/host responses, chooses the demo device
from the sidebar's device selector, verifies real keyboard insets, Back,
sending/stopping and that an export's Download opens Android's save dialog,
then reloads the real entry page. It preserves application data and credentials.
These fixture checks do not establish an end-to-end run on your real computer;
that requires signing into GitHub and choosing your online device.
