# Desktop conversation export

For a saved local, remote Work, or Cloud conversation, **Export conversation** opens a modal
with **Download** and **Share**. The modal captures the selected conversation,
workspace and archive placement; changing the active conversation cannot redirect
an outstanding export. Both actions use the existing standalone HTML visualizer. Work includes its
recorded tool inputs/outputs and direct subruns; Cloud uses its committed visible
message projection, including tool inputs/results and terminal status.

Desktop Download uses the native save dialog, then opens the saved file.
Browsers download the standalone HTML directly. Cancelling the
save dialog keeps the export modal open. A file that was saved but could not be
opened is reported as saved, with its path.

Share uses the current client's OpenSeek account. If sign-in is required, the
modal offers the existing sign-in flow; the user then clicks Share again.
Local native Work captures and uploads in its host using that host's account.
Remote Work first obtains a single upload grant with the client's account,
then sends only that grant, key and source metadata to the selected host's
`session.share`. The host captures once and uploads HTML and JSON through
native HTTP; no full client account token is given to the remote host.
Cloud calls its server-side `/share` operation, which exports and uploads the
captured visible messages. The frontend does not download snapshots to upload.

The API accepts publication at `/v2/shares`; public links remain under
`/v1/shares/<id>`. An account 401 requests sign-in; a grant 403 preserves the
account and leaves Share available for retry. Late results cannot retire a
replacement account. Object-storage credentials remain server-side.
The server returns the completed public URL; the modal shows it as a selectable
field with a copy-to-clipboard button. Successful copying changes the icon to a
green check; failures show an error. Downloading afterward keeps the completed
link available in the same modal.

The modal explains that anyone with the link can view the uploaded snapshot for
seven days. Only clicking Share starts publication. Closing the modal does not retract a snapshot already published; a late result
does not reopen it. A failed or
lost internal upload attempt is retried once with identical content and the same idempotency
key, so a retry can never create a second share. If that retry also fails, the
modal shows the server's error text when it sent one, or the transport failure
otherwise. A disconnected outer RPC/Cloud request is not automatically
resubmitted; another explicit Share click starts a new capture with a new key. The full multipart request
must fit the server's 20 MiB limit. Share titles are trimmed and capped at 1024
UTF-8 bytes on a Unicode character boundary; this metadata limit never
truncates the HTML or JSON conversation.

## Native commands

`session.export` is the window-only local save operation and requires
`{session, workspace, title, archived}`. `session.snapshot` captures those same
source fields for remote/browser downloads. `session.snapshot_save` saves a
client-rendered Cloud download through the window.

`session.share` is available to both transports and requires
`{generation,source,idempotency_key,authorization}`. Only the native window
may choose local account authority; device channels require an upload grant.
It returns `{status:"shared",url}`, `{status:"sign_in_required"}`, or
`{status:"failed",message}`. Progress returns to the originating connection.
The launch-token local debug console reports sharing as unsupported and
suggests the native Dev app or hosted browser; downloads remain available.

## Verification

The automated checks are the `frontend/export_dialog` JS tests,
`desktop/backend/api` and `desktop/backend/internal/shares` native HTTP tests, `protocol/session_share_test.mbt`,
and `desktop/e2e/tests/export_conversation.spec.js` after building the browser
package. Browser tests substitute the native transport, not the product UI.

The end-to-end check against a real deployment is manual: share a short
non-sensitive conversation, open the link in another browser, and verify the
file page previews the HTML and downloads both files without requiring login.
An HTTP 404 on creation means the signed-in deployment or its proxy does not
expose the share endpoint; the error names the server that was asked.
