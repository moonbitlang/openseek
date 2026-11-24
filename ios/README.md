# SeekMoon for iPhone (local prototype)

Open `ios/SeekMoon.xcodeproj` in Xcode, select **SeekMoon** and an iPhone simulator (iOS 17.4 or newer), then press **⌘R**. No developer account is needed for the simulator. To run on your iPhone, select it as the destination and choose your own development team in Signing & Capabilities. There is no release workflow for this project.

The app opens the hosted `/cloud` in a persistent WKWebView. Cloud chats need no computer; for Connect, turn on Remote access in the desktop app, sign in with the same account and choose your online computer from the sidebar. The shared MoonBit/Rabbita page owns conversation history, streaming, approvals, stop and reconnection. The iPhone does not run an agent. Internet access is required for launch; a failed document load offers Retry and Open Cloud.

Find exported conversations and downloaded workspace files in **Files → Browse → On My iPhone → SeekMoon**. Downloading the same filename again keeps both copies.

The shell appends `SeekMoonIOS/0.1.0` to the WebView user agent. The public page is the server's selected browser release, not the frontend in your checkout. It may still show browser download links. The prototype has no native command bridge, frontend updater, native push or background socket service. Returning to the foreground keeps the current web view; after process termination the app reopens the last saved Cloud or device page (path only). Unsaved drafts across process termination are not guaranteed.

## Sign-in

The shell intercepts the console's `/v2/auth/login` navigation and opens GitHub sign-in with `ASWebAuthenticationSession`. A new iOS callback scheme was rejected by the hosted account start route during prototyping. Instead, the shell uses the existing [desktop PKCE protocol](../docs/remote-protocol.md#authentication): a random verifier and state, and a temporary listener bound only to `127.0.0.1` on an OS-assigned port. An accepted `/cb` redirects the browser into this app's authentication session. The listener accepts one matching reply and is closed on completion, cancellation or timeout. The code is exchanged at the relay over HTTPS; the account token never enters a URL. Only a trusted console document can receive the result in its existing `seekmoon.account.v1` store. The shell reloads that page after sign-in or cancellation.

Keep the authentication sheet in the foreground while signing in. A dedicated, server-approved iOS callback would remove the loopback step. No server change is needed to use the documented port flow. Test the complete handoff on a physical iPhone before relying on it for distribution.

## Check the prototype

From the repository root, list installed devices with `xcrun simctl list devices available`. Substitute an installed iPhone name for `iPhone 17` if necessary:

```sh
xcodebuild -project ios/SeekMoon.xcodeproj -scheme SeekMoon \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ios/.artifacts/simulator -parallel-testing-enabled NO test
```

The native tests use a loopback callback and disposable WebKit storage. To check the live entry point, run the same command with `-scheme LiveSmoke` on a signed-out simulator with internet access. This UI test opens the hosted login button, cancels the system sign-in sheet and repeats the attempt. Neither test suite submits real credentials.

For the remaining acceptance checks, use your own account and, for Connect, your own online host:

1. Open Cloud. Start GitHub sign-in, cancel, then try again. After completing sign-in, the same page should show your account. Quit and reopen; the account should still be available.
2. Without choosing a device, send one Cloud message and check the streamed response. Type a multiline draft with the phone keyboard open; the last line and Send should remain visible.
3. In the sidebar, choose your computer, send a message and verify the same turn on the desktop. Stop a running turn; the conversation should show its stopped state.
4. Background the app or briefly disconnect the host. Return to the app; verify the selected conversation, the final state of the turn, and that reconnecting does not send it again.

**Local verification (2026-11-18):** On an iPhone 17 simulator running iOS 26.5, all three native tests passed. The hosted page opened and the live UI test cancelled and reopened the system sign-in sheet. The generic iPhone device build also compiled without signing. Separate Playwright WebKit tests at phone width exercised the hosted 0.2.56 frontend with local test data: Cloud sent one message and kept a multiline draft at reduced viewport height; Connect sent once, stopped and reconnected. That release requires host protocol 10. The protocol-8 fixture in this checkout correctly displayed “Device unavailable”; the compatible fixture from upstream commit `8a1b8e1fda22` exercised the successful path. These browser tests did not use a real account, real phone keyboard or live desktop host.

**Live Connect check (2026-11-23):** The iPhone 17 simulator opened a real Mac workspace with both the hosted frontend and desktop on 0.2.60 (host protocol 14). From the iPhone sidebar, select **Work** (`</>`), tap the Mac's project, then tap the pencil to start a conversation. With the API key configured in the desktop app's isolated Codex login, selecting GPT-6.2-Sol and sending “只回复 OK” produced “OK” on the phone. The Mac recorded that same turn once.

If Work is missing, first check **Settings → Connections → Remote access** on the Mac. On the network used for this check, the desktop's direct connection to the relay timed out even though a browser could reach it through the system proxy. With DOVE in virtual network adapter mode the desktop showed **Online**, and reopening the iPhone app refreshed its device list. Changing the OpenAI key does not affect device registration.
