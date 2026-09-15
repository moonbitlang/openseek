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
An HTTP 401 clears the rejected persisted login before offering sign-in. A late
rejection never clears a newer registration selected during the upload.
The native process captures records once and sends both HTML and JSON to
`POST /v1/shares` at the credential's issuing server. JSON contains the same
visualizer dataset embedded in HTML: request paths map to serialized session
listing and event-envelope responses, preserving raw JSONL event records.
Neither bearer credentials nor object-storage credentials enter the frontend.
The server returns the completed public URL; the modal shows it as a selectable
field with a copy-to-clipboard button. Successful copying changes the icon to a
green check; failures show an error. Downloading afterward keeps the completed
link available in the same modal.

The modal explains that anyone with the link can view the uploaded snapshot for
seven days. Only clicking Share starts publication. Closing the modal does not
cancel an upload already sent; a late result does not reopen it. A failed or
lost attempt is retried once with identical content and the same idempotency
key, so a retry can never create a second share. If that retry also fails, the
modal shows the server's error text when it sent one, or the transport failure
otherwise; another Share click starts a new upload. The full multipart request
must fit the server's 20 MiB limit. Share titles are trimmed and capped at 1024
UTF-8 bytes on a Unicode character boundary; this metadata limit never
truncates the HTML or JSON conversation.

## Native commands

Both commands are window-only and require `{session, workspace, title, archived}`.
There is no destination path or server URL in the frontend request.

- `session.export` returns `{path?, opened}`.
- `session.share` returns `{status: "shared", url}`,
  `{status: "sign_in_required"}`, or `{status: "failed", message}`.

## Verification

The automated checks are the `frontend/export_dialog` JS tests,
`backend/internal/shares` native HTTP tests, `protocol/session_share_test.mbt`,
and `desktop/e2e/tests/export_conversation.spec.js` after building the browser
package. Browser tests substitute the native transport, not the product UI.

The end-to-end check against a real deployment is manual: share a short
non-sensitive conversation, open the link in another browser, and verify the
file page previews the HTML and downloads both files without requiring login.
An HTTP 404 on creation means the signed-in deployment or its proxy does not
expose the share endpoint; the error names the server that was asked.
