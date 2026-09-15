# Desktop conversation export

For a saved local OpenSeek conversation, **Export conversation** opens a modal
with **Download** and **Share**. The modal captures the selected conversation,
workspace and archive placement; changing the active conversation cannot redirect
an outstanding export. Both actions use the existing standalone HTML visualizer,
including the conversation's recorded tool inputs/outputs and direct subruns.

Download uses the native save dialog, then opens the saved file. Cancelling the
save dialog keeps the export modal open. A file that was saved but could not be
opened is reported as saved, with its path.

Share uses the desktop's existing OpenSeek login. If sign-in is required, the
modal offers the existing browser sign-in flow; the user then clicks Share again.
The native process captures records once and sends both HTML and JSON to
`POST /v1/shares` at the credential's issuing server. JSON contains the same
visualizer dataset embedded in HTML: request paths map to serialized session
listing and event-envelope responses, preserving raw JSONL event records. Neither bearer credentials nor S3/OSS credentials enter the frontend.
The server returns the completed public URL and expiry; the modal displays only
the URL. Opening it shows a file page with HTML preview/download and JSON
download actions. The URL is selectable, with a copy-to-clipboard button on its right.
Successful copying changes the icon to a green check; failures show an error.
Downloading afterward keeps the completed link available in the same modal.

The modal explains that anyone with the link can view the uploaded snapshot for
seven days. Only clicking Share starts publication. Closing the modal does not
cancel an upload already sent; a late result does not reopen it. A lost HTTP
response is retried once with identical content and the same idempotency key.
If publication still cannot be confirmed, the UI says that a share may exist;
another Share click starts a new upload. The full multipart request must fit the
server's 20 MiB limit.

## Native commands

Both commands are window-only and require `{session, workspace, title, archived}`.
There is no destination path or server URL in the frontend request.

- `session.export` returns `{path?, opened}`.
- `session.share` returns `{status: "shared", url, expires_at}`,
  `{status: "sign_in_required"}`, or `{status: "failed", message}`.

## Smoke test

1. Build the desktop from this checkout:
   `moon run ./desktop/package/macos -- --no-open`.
2. Quit the existing app, then launch the built executable with the intended
   sign-in server. The default is `https://openseek-api.moonbitlang.cn`; the
   current Settings UI does not provide a server selector. For staging, run
   `OPENSEEK_SERVER_URL=https://openseek-api-staging.moonbitlang.cn ./desktop/dist/SeekMoonDev.app/Contents/MacOS/seekmoondev`
   from the checkout root. A server switch signs out the previous registration;
   sign in again through Settings or the export dialog. The share destination
   comes from that login. Keep this environment override when relaunching for
   staging tests; opening the app normally uses the default server again.
   Use the server's canonical HTTPS origin (its `OPENSEEK_BASE_URL`), not its
   internal IP: OAuth redirects to the canonical origin, and its host-only
   Secure state cookie cannot follow a login started on an HTTP IP address.
3. Open a local conversation containing messages, then click **Export
   conversation**. No upload or native save dialog should start yet.
4. Choose **Download**, cancel the save dialog, and verify the modal stays open.
   Download again, save the HTML, and verify that it opens with the conversation.
5. Choose **Share** on a short non-sensitive conversation. While uploading,
   Download and Share are disabled. On success, verify the link is displayed.
6. Click the copy button and verify its icon changes to a green check. Paste
   the link in another browser. Verify the file page lists HTML and JSON,
   Preview opens the conversation, and both Download actions save the right
   file without requiring login. This is the deployment/OSS
   check; mocked browser tests do not establish it.
7. Check Escape/Close, resize while the modal is open, and verify that a failed
   upload leaves Download available. Signed-out sharing should offer Sign in.

The focused automated checks are the `frontend/export_dialog` JS tests,
`backend/internal/shares` native HTTP tests, `protocol/session_share_test.mbt`,
and `desktop/e2e/tests/export_conversation.spec.js` after building the browser
package. Browser tests substitute the native transport, not the product UI.

An HTTP 404 on creation means the requested deployment or proxy did not expose
the share endpoint. Check the server shown in the error and its routing/version.
An unauthenticated POST to `/v1/shares` should return 401 when the share handler
is available; this checks routing/authentication, not a successful storage upload.

If GitHub login returns `missing state cookie`, check that login started at the
same canonical HTTPS origin used by `/v1/auth/callback`. Restart the desktop
with that origin and begin a fresh sign-in; refreshing the failed callback does
not recreate the state cookie.
