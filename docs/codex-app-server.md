# Codex app-server in OpenSeek Desktop

OpenSeek Desktop starts one `codex app-server` child process. Codex and OpenSeek
conversation lists share the global left sidebar; selecting either source swaps
the main transcript and composer without creating a second nested application
shell. Codex remains the owner of its account and thread data, separate from
OpenSeek's existing engine and conversation store.

The sidebar presents Workspaces, Codex, Chats, and Archived chats as peer
collapsible sections in one scroll lane. Folding a section is page-local view
state; it never archives, reloads, or otherwise mutates either conversation
store.

The browser code mirrors that ownership. `desktop/frontend/codex` is a
standalone MoonBit package containing the Codex state, update function,
app-server calls, sidebar rows, approvals, and composer wiring. It converts
app-server items into the same display-ready transcript items OpenSeek uses;
the root `desktop/frontend` package renders both through one conversation
transcript view. The root package also selects the main screen, combines the
two conversation lists, and supplies shell-owned commands for Sidebar,
Terminal, Files, and external links. Shared composer layout and SVG icons live
in `desktop/frontend/composer` and `desktop/frontend/icons`; Codex owns no
second transcript renderer or conversation chrome.

The implementation follows the [official app-server
protocol](https://developers.openai.com/codex/app-server). The native process
uses app-server's newline-delimited JSON over stdin/stdout; stdout is reserved
for protocol messages and stderr is drained separately. The connection sends
`initialize`, waits for its reply, and then sends `initialized` before it serves
page requests.

## Process and data ownership

- One `CodexActor` owns one app-server child for the Desktop process lifetime.
  All Desktop and relay clients share that connection and Codex account.
- Every run resolves `codex` from the user's login-shell `PATH`. SeekMoon does
  not download, install, update, or bundle a Codex runtime.
- App-server receives an isolated `CODEX_HOME` under the per-user runtime
  directory (see "Isolated Codex home" below). It never touches the CLI's
  `~/.codex`. OpenSeek does not read, copy, persist, or relay an API key or
  ChatGPT token; the token stays inside the isolated home's `auth.json`,
  protected by the OS keychain.
- A disconnect drops streamed presentation state. After reconnect, the page
  calls `thread/read` with `includeTurns: true`; that reply is the authoritative
  history snapshot. An idle stored-task Send calls `thread/resume` immediately
  before `turn/start`; an `inProgress` task sends `turn/steer` directly, so the
  page does not cache writer state or race rollout materialization.
- `item/completed` replaces any accumulated delta text. Deltas are display-only
  and are not treated as durable history.

## Exposed Desktop methods

OpenSeek does not expose an arbitrary app-server proxy. The Desktop catalog is
limited to:

- account read, ChatGPT login start/cancel, and logout;
- model list;
- thread start, resume, read, list, rename, archive, unarchive, and compact;
- turn start, steer, and interrupt;
- pending server-request list and typed server-request response.

`codex.thread.list` preserves Codex's default interactive source selection and
shows the account's interactive history in the global sidebar. This matters
because app-server clients can persist interactive threads with the `vscode`
source label; forcing only `appServer` would hide a thread immediately after
OpenSeek created it. The method sets `useStateDbOnly: true` so a page refresh
cannot trigger a full JSONL scan-and-repair pass that exceeds the Desktop
request deadline.
App-server reports only each thread's exact `cwd`; it does not expose the
Codex App's project-to-worktree catalog. The native Codex package therefore
resolves `git worktree list --porcelain` and adds `projectRoot` to thread list,
start, resume, and read replies. The sidebar groups by that main checkout and
lists conversations directly beneath it; linked worktrees remain execution
locations and are not rendered as another navigation level. Existing non-Git
directories map to themselves, while a missing or deleted cwd is left without
a project instead of being presented as a project root.

The app-server connection opts into `capabilities.experimentalApi`, and the
Codex composer exposes three permission modes. The native command layer maps
the selected mode to app-server fields instead of accepting arbitrary sandbox
JSON from the page:

- **Request approval:** `approvalPolicy: "on-request"`,
  `approvalsReviewer: "user"`, and `permissions: ":workspace"`;
- **Approve for me:** `approvalPolicy: "on-request"`,
  `approvalsReviewer: "auto_review"`, and `permissions: ":workspace"`;
- **Full access:** `approvalPolicy: "never"` and
  `permissions: ":danger-full-access"`; no reviewer is sent because this mode
  does not produce interactive approval requests.

The page defaults to **Approve for me** and requires confirmation before it
selects **Full access**. `codex.thread.start`, `codex.thread.resume`, and
`codex.turn.start` all send the current selection. They therefore intentionally
override the isolated Codex home's sandbox and approval defaults; the named
`permissions` profile is sent instead of the legacy `sandbox` field.
`codex.thread.start` also sets `serviceName: "openseek_desktop"`.

The model picker also uses `model/list` as the authority for reasoning effort.
When a model reports `supportedReasoningEfforts`, the composer shows a separate
Reasoning picker beside the model picker. The current choice is checked again
when the model changes, falling back to that model's `defaultReasoningEffort`
and then its first supported effort. The page stores the choice locally with
the selected model.

New turns pass the checked choice as `turn/start.effort`, including the first
turn in a newly created worktree. `turn/steer` has no effort override, so a
steered prompt keeps the active turn's settings. Compatibility is catalog
driven: if an older app-server omits reasoning metadata, OpenSeek hides the
picker and omits `effort` instead of guessing supported values.

## Isolated Codex home

OpenSeek Desktop gives its app-server a dedicated `CODEX_HOME` instead of
sharing the CLI's `~/.codex`:

- macOS: `~/Library/Application Support/SeekMoon/codex`
- Windows: `%LOCALAPPDATA%\SeekMoon\codex`
- Linux and other POSIX: `$XDG_DATA_HOME/SeekMoon/codex` (fallback `~/.local/share/SeekMoon/codex`)
- development (unbundled Moon host): `<checkout>/desktop/target/dev-state/codex`

The directory is created at startup and restricted to its owner with mode
`0700` on POSIX hosts. The spawn sets `CODEX_HOME` explicitly, so it wins over
any value the login-shell environment inherited; every process the app-server
later starts inherits the same home, so nested codex calls, sandbox approvals,
and tool runs agree with the app-server on auth and config. If the home cannot
be determined or created, the Desktop logs a warning and falls back to the
inherited environment — the pre-isolation behavior.

Isolation is deliberate, and its costs are accepted:

- **Separate login.** `auth.json` lives in the home, so a user who is signed
  in to the CLI or VS Code must sign in once in the Desktop. Logout, token
  rotation, and revocation apply per home.
- **Default configuration.** The home starts empty, so `config.toml` defaults
  apply — sandbox mode, approval policy, MCP servers, and model settings from
  the CLI config are not inherited.
- **Separate history and worktrees.** The sidebar lists only threads in the
  Desktop's own `state.db`, and managed worktrees are checked out under the
  isolated home, not the CLI's.

Because the home lives under the app's per-user runtime directory, clearing
that directory removes every Codex artifact the Desktop ever created — the
CLI's `~/.codex` is never part of that scope.

## Workspace panels

App-server supplies each thread's working directory as `thread.cwd`; it does
not render a terminal or file editor. OpenSeek reuses its existing Terminal and
Files panels for the selected Codex conversation. Both panels run on the
focused device, use the Codex thread id as their session identity, and use the
thread cwd as their workspace. Switching the global sidebar selection re-roots
the panels to the newly selected OpenSeek or Codex conversation.

The file panel stays disabled until the selected Codex thread has a non-empty
cwd. OpenSeek does not guess a filesystem directory from a Codex thread id.
The terminal can still open a scratch shell for an active thread whose cwd is
absent.

After a file read succeeds, the editor reconstructs the exact root from the
host-returned absolute file and the requested relative path. Diagnostics,
hover, definition, and references send that root plus a relative path to the
language host, so a Codex cwd or linked worktree does not have to appear in
OpenSeek's attached-workspace list.

The Codex composer uses the same workspace-symbol service as the OpenSeek
composer: `#query` calls the Desktop host's `lsp.workspace_symbols` method and
keeps the returned file and range when the symbol is selected. `@query` is
reserved for Codex app-server's `fuzzyFileSearch`; selected files remain native
app-server mention inputs. Both searches are scoped to the selected thread's
exact cwd.

A successful app-server `thread/start`, `thread/resume`, or `thread/read`
reply authorizes only its exact `(thread id, cwd)` pair for the lifetime of the
Desktop process. Files and Terminal must present that same pair; a browser
cannot substitute another absolute path. This authorization does not silently
add a Codex cwd to OpenSeek's persisted workspace list, and archiving the Codex
thread revokes it.

The Proton page and an authenticated owner using OpenSeek's relay see the same
reviewed method catalog. The app-server stdio stream is never exposed on a
socket, and remote callers cannot choose an arbitrary app-server method name.

## Events and approvals

The native process publishes three Desktop events:

- `codex.status_changed` reports `starting`, `ready`, or `unavailable`;
- `codex.notification` carries app-server notifications as `{method, params}`;
- `codex.server_request` carries a typed approval/input request as
  `{request_id, method, params}`.

The JSON-RPC reader never waits for a browser. Notifications and reverse
requests enter a bounded Actor queue; losing an event closes the connection so
the page reconnects and re-reads durable state instead of displaying an
untrustworthy partial turn. Live reverse requests are kept by their exact
JSON-RPC id and can be listed after a page reload.

The UI answers these app-server request methods:

- `item/commandExecution/requestApproval`;
- `item/fileChange/requestApproval`;
- `item/permissions/requestApproval`;
- `item/tool/requestUserInput`;
- `mcpServer/elicitation/request`.

An unexpected reverse request receives JSON-RPC method-not-found. It is not
rendered as a raw response editor.

## Runtime discovery

Codex integration is optional. On startup, SeekMoon imports the user's
login-shell environment, starts `codex app-server` through `PATH`, and performs
the normal initialize handshake. A missing command, a CLI without the
`app-server` subcommand, or a failed handshake marks Codex unavailable without
preventing OpenSeek conversations from working.

SeekMoon deliberately does not probe private Codex App state or copy its
runtime. Installing and updating the Codex CLI remains the user's or system
administrator's responsibility. The discovered command runs against the
Desktop's isolated `CODEX_HOME` — its own account, configuration, sandbox,
and approvals — never the CLI's `~/.codex` state.

## Verification

The narrow protocol tests cover concurrent JSON-RPC replies, peer requests,
asynchronous responses, queue rejection, close behavior, and notification
routing. Frontend tests cover authoritative completed items and exact
question-id response shapes. A release smoke test requires a compatible
`codex` on the login-shell `PATH` and should additionally:

1. launch the packaged app and select a Codex conversation in the left sidebar;
2. confirm account and model state loads without exposing credentials (the
   first run needs a Desktop-side sign-in: the isolated home has its own
   `auth.json`);
3. create a thread in a disposable workspace and run a short turn;
4. exercise one approval or user-input request;
5. reload the page during an active request and confirm the request reappears;
6. open Terminal and Files, then confirm both use the selected thread's cwd;
7. switch between Codex conversations and confirm both panels follow the cwd;
8. quit the app and confirm the app-server child exits.
