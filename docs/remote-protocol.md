# OpenSeek Remote Protocol (v2)

The wire protocol between a browser client and an OpenSeek **host process**
— the desktop app's native process, which owns the engine and the host ops.
The host runs no server: at startup it dials out to a **relay** and
registers; browsers reach it through the relay, which serves the frontend
bundle and splices WebSockets without understanding a byte of the protocol.

The desktop window itself does not use this protocol. It talks to the host
over proton's in-process `__MoonBit__` bridge — same method catalog, same
payloads, no wire. The frontend picks its transport by origin: a `proton://`
page uses the bridge, anything else opens the WebSocket below.

This document is the contract. The implementation follows it, not the other
way around.

## Host process ownership

The native process owns every engine process, language server, relay socket,
and filesystem watcher. Long-lived work is attached to an app- or
connection-lifetime actor rather than to the request that happened to create
it:

- `EngineActor` owns serve processes and durable-session followers.
- `LspPoolActor` owns the language-server actors shared by the host.
- `RelayActor` owns the control connection and creates one `WsClientActor`
  for each relayed client.
- Every Proton or WebSocket client owns a separate `HostConnection`, whose
  `FsWatchActor` serves only that client's `fs.watch` state and whose
  terminal state owns only that client's PTYs; filesystem and terminal
  notifications return only to the owning client.
- `DesktopBridgeActor` owns the current Proton page attachment and forwards
  the shared catalog notifications to it.

Closing the Proton application cancels these owners together. A request may
post work to them, but cancelling or reloading that request cannot orphan a
socket, subprocess, or watcher.

## Transport

All HTTP lives at the relay. Browser releases are versioned alongside Desktop
releases; JSON/WS APIs live under `/v1`:

| Route | What |
|---|---|
| `GET /console/` | The server-selected Browser release |
| `GET /console/releases/v<version>/index.html` | One published Browser bundle. `?device=<id>` is required and fixes the page/tab to that device; optional `?workspace=<path>` selects where its first conversation lands. Packaged Desktop links here with its installed version |
| `GET /d/<device>/…` | Retired: `302` to `/console/?device=<device>` with the original query appended, so old deep links keep their device target |
| `GET /healthz` | Relay liveness probe, `200 ok` |
| `/v1/auth/*`, `/v1/devices…` | The relay's own auth and device APIs (see Authentication) |

Everything else — commands, queries, and host-pushed events — travels over
`GET /v1/devices/<device>/ws`, upgraded from the same origin the bundle was
served from and spliced through to the host. A browser page takes its one
`<device>` from the required `?device=` query and verifies it against
`GET /v1/devices`; other roster devices need their own page/tab. Frames are
JSON text, shaped as **JSON-RPC 2.0**:

```jsonc
// client → host: request
{"jsonrpc": "2.0", "id": 1, "method": "agent.start", "params": {…}}

// host → client: response (exactly one per request, either form)
{"jsonrpc": "2.0", "id": 1, "result": {…}}
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32000, "message": "…"}}

// host → client: notification (no id, no reply expected)
{"jsonrpc": "2.0", "method": "agent.event", "params": {…}}
```

Request `id`s are client-assigned and client-scoped (a monotonic counter is
fine). Responses may arrive out of order relative to other requests — the
`id` is the correlation. Batch requests are not supported. A request frame
larger than 1 MiB is closed with WebSocket code 1009; operation payloads carry
prompts, paths, and settings, never transcript snapshots or file contents.

Remote delivery trims high-volume transcript objects whose canonical form is
delivered by `session.event`. This is the protocol baseline and applies only to
named durable sessions. Session-less runs retain the complete legacy stream
because they have no `session.event` source. For a durable run, the pushed
`agent.started` remains with `task: ""`;
`reasoning_message` and `assistant_message` remain as stream-settlement signals
with `content: ""`; `tool_result`, `auto_compaction_finished`, `agent_finished`,
and `context_yield` are omitted. The separate `agent.finished` lifecycle
notification remains, including its optional `answer`;
`compaction_finished` remains with an empty `summary` so it still closes the
lifecycle state. Deltas, usage, step progress, tool-decode errors, runtime
status, steer receipts, and all other run/compaction lifecycle and error events
are unchanged. The desktop's in-process bridge continues to receive the hub's
complete stream; this trimming is specific to remote WebSocket delivery.

### Filesystem path encoding

Every field below described as an **absolute path** carries the slash-rooted
path component of an OpenSeek resource URI, not a host-native spelling and not
the complete URI. A POSIX path is unchanged (`/home/u/work`); a Windows drive
path gains the URI root slash and uses forward slashes (`C:\work` becomes
`/C:/work`). The WebSocket or in-process channel already identifies the owning
device, so these fields carry no URI scheme, authority, query, or fragment.
The frontend combines the channel identity and path as an `openseek:` URI.

UNC paths are unsupported: the resource URI authority belongs to the owning
device and cannot also encode a UNC server. The host rejects them at the
protocol boundary. Fields described as **relative paths** remain
slash-separated strings relative to their operation's explicit root.
`fs.browse` request input is the
one user-entry exception: its editable value may use the target host's native
syntax, start with `~`, or repeat a URI path from the preceding browse reply;
an absent value selects the host home directory. Its absolute reply fields
always use the encoding above.

## Authentication

Auth terminates **at the relay**; the JSON-RPC wire above carries no
credentials and is unchanged by it. Device ids are stable database ids,
not secrets — the barrier is ownership:

- **Browsers** sign in with GitHub OAuth at the relay (`/v1/auth/login` →
  callback → `session` cookie, HttpOnly/SameSite=Lax, 7-day sliding).
  The data WebSocket upgrade on `/v1/devices/<device>/ws` requires a
  session whose user **owns** that device; anything else is 401/404.
- **Hosts** register over the control WebSocket with an `odt_` **device
  token** issued by the relay at sign-in time. The relay stores only a
  keyed hash; revoking a device invalidates the token and disconnects any
  live tunnel.
- **Desktop sign-in** is loopback OAuth with PKCE (RFC 8252 shape): the
  host starts a one-shot listener on `127.0.0.1:<random>`, opens the
  system browser at `<server>/v1/auth/desktop/start?state&code_challenge&
  port&name`, the signed-in user clicks **Allow** once, the browser
  bounces a one-time code to the listener, and the host swaps it (plus
  its PKCE verifier; the challenge is standard S256 — the unpadded
  base64url of `sha256(verifier)`, RFC 7636) at
  `POST /v1/auth/desktop/exchange` for `{device_token, device, user}` —
  the exchange **is** device registration. The host persists the token
  (`auth.json` in its runtime dir, 0600). Development overrides:
  `OPENSEEK_DEVICE_TOKEN` + `OPENSEEK_RELAY_URL` pin the connector config
  directly (bypassing sign-in), and `OPENSEEK_SERVER_URL` points the
  sign-in flow at an ad-hoc server regardless of the settings' selection.

The relay's server implementation and HTTP surface (OAuth routes, the devices
API, and schema) live in the openseek-api repository; its
`docs/relay-auth-design.md` specifies that account layer. This repository keeps
only the desktop-side connection code in `desktop/internal/remote` and the four
control-frame definitions in `desktop/tunnel`.

## Errors

| code | meaning | v1 equivalent |
|---|---|---|
| `-32700` | unparsable frame | — |
| `-32600` | not a valid JSON-RPC request | — |
| `-32601` | unknown method | 404 unknown op |
| `-32602` | params failed to decode | 400 `PayloadError` |
| `-32000` | engine error (`EngineError` — busy conversation, spawn failure, …) | 409 |
| `-32001` | host error (`HostError` — bad path, LSP failure, …) | 409 |
| `-32603` | internal error | 500 |

`error.message` is the user-facing text. `error.data` is unused for now.

## Connection lifecycle: reconnect = resync

There is no stream-resume machinery: no connection cursor and no replay of
transient notifications. (The one sequence that exists is per-session and
durable, not per-connection:
`session.event` carries the store's own event sequence — see *The durable
transcript* below — and a reconnect recovers missed commits by re-reading,
never by replay.) The sole lifecycle exception is `agent.runs`'s targeted,
process-lifetime settlement state for owners the reconnecting client names;
it is a state query, not an event log. A connection delivers events from the
moment it exists; whatever a client missed while disconnected it recovers by
re-reading state:

1. Connect the WebSocket. The host sends `agent.connected` as the connection's
   first notification, then starts forwarding the remote delivery stream.
2. Resync: `session.list` + `agent.runs` (and reload whatever conversation
   is open via `session.load`). The client gives `agent.runs` the exact owners
   from its request-time frontier: `{session, run_id}` after Started, or
   `{session, submission_id}` while a start is in flight or delivery became
   unconfirmed before its run id arrived. The reply contains the **complete**
   in-flight set plus matching completed settlements retained by this host
   process. The in-flight set introduces runs the client has
   never seen, and any run the client still shows that the reply lacks
   ended while it was away (its terminal notification will never be
   replayed) and must be closed client-side. That negative-set decision is
   limited to the exact per-session lifecycle state the client captured before
   issuing this `agent.runs` request (idle/last run, starting `submission_id`,
   or open run id). Any local steer reconciliation caused by that negative row
   is likewise limited to the exact submission ids present at the request's
   frontier; a steer submitted while the reply is in flight keeps its own
   receipt path. Positive rows use the same frontier: a row is replayed only if
   that session still has its captured state. A new `agent.started`,
   `agent.finished`, or Send while the request is in flight therefore wins over
   both stale presence and stale absence in the older reply. A settlement is
   accepted under the same owner gate; an abnormal settlement is returned only
   once its exact durable frontier is known (including sequence zero). One
   atomic reply may contain a predecessor settlement and that session's active
   successor, and clients apply both. The whole reply is also tagged with the
   connection generation, so no row from a pre-reconnect request crosses a
   later readiness boundary.
3. Race note: notifications may arrive before the resync replies. This is
   harmless by construction — streaming deltas are ephemeral display state,
   and every completed step is delivered durably by `session.event` (legacy
   clients also receive the full `agent.event` message). A client buffers
   commits while loading and reconciles them against the snapshot watermark.

What this costs, deliberately: transient events that occurred while
disconnected (`usage` ticks, steer receipts, background notices) are gone —
none of them carry state a resync cannot rebuild or safely ignore. A run
that *finished* while the client was away is visible through `session.load`;
its targeted `agent.runs` settlement supplies lifecycle outcome and the exact
zero-durable case where no record exists to load. Settlements live only for the
host process lifetime. After a host process restart there is no durable
submission-id index, so a pre-restart unconfirmed input remains conservatively
unresolved rather than being guessed.

Slow clients are disconnected, not throttled and not silently dropped
frame-by-frame: when a connection's outbound queue overflows, the host
closes it, and the client reconnects into the resync path above.

The in-process bridge does not use WebSocket reconnect or capability
negotiation. It can still be recreated across a host restart: each
`BridgeReady` transition makes the desktop rebuild host-derived state, so that
readiness resync follows the same idempotent, race-tolerant rules.

## Method catalog

`params` is always a JSON object; `{}` when a method takes nothing.
Optional fields (`?`) are absent when unset — the protocol never encodes
request-side absence as `""`, `0`, or another in-band sentinel. The one
reply-side compatibility exception is a missing file's
`fs.stat_files.stats[].sig: ""`.

### agent.* — runs

Run ids are opaque strings minted by the host, one per accepted prompt.
They use 128 bits of OS randomness and are not intentionally reused across
host restarts, so a client may safely retain a pre-restart run id. Clients
compare them for equality only.

`submission_id` is a separate, optional opaque string minted by the client.
It must contain non-whitespace content and be at most 128 UTF-8 bytes; the host
treats a blank or overlong value as absent rather than retaining or echoing it.
On `agent.start` the host echoes it unchanged in the corresponding
`agent.started`; on `agent.steer` it is echoed in that submission's eventual
`steer_applied` or `steer_dropped` event. This identifies the exact live
submission that owns the returned run or receipt, even when two steers have
identical text. The `agent.started` echo establishes run ownership but not
durability—it is emitted before the host writes the prompt. An `agent.start`
result of `accepted` proves the complete stdin command was written, not that
the User item reached the store. Clients therefore retain a recovery copy
until a normal Terminal-backed finish proves the User append, or an abnormal
exact durable frontier reconciles it (sequence zero restores it for
resubmission). This is lifecycle correlation only; durable transcript items
still come from `session.event`. Old clients omit it, and old hosts omit the
echoes.

| method | params | result |
|---|---|---|
| `agent.start` | `{task, submission_id?, model?, max_steps?, session?, workspace?}` — no credentials or store path: the host resolves settings and durable placement; `workspace` is honored only when registered. A session bound to one of the workspace's worktrees (`worktree.create` binds at creation) runs in that checkout — the start never names or mutates worktrees | `{run_id, status, …}` — `accepted` after the complete prompt command is written; a post-`started` write failure returns `failed`, while pre-`started` failures use the error response |
| `agent.cancel` | `{run_id?}` (absent = the latest run) | cancel outcome |
| `agent.steer` | `{text, run_id?, submission_id?}` | steer outcome |
| `agent.compact` | `{session, model?, max_steps?, workspace?}` — `agent.start` minus `task`: a conversation resumed after a restart has no live process, and compacting spawns one with these settings | compaction outcome |
| `agent.goal` | `{session, text?, auto?, model?, max_steps?, workspace?}` — sets the session's standing goal to `text`, or clears it when `text` is absent; the engine settings match `agent.compact`'s, and a blank `session` is refused rather than falling through to the session-less slot. `auto` arms the engine's autonomous continuation and is **currently rejected**: serve announces the turns it starts with `goal_continue`, which this host does not yet fold into a run's lifecycle, so an autonomous turn would leave the engine looking idle to `agent.start` | `{delivered}` — delivery, not durability: the command reached a live engine's stdin. The goal itself is confirmed by the `[goal]` / `[goal cleared]` runtime-notice arriving as a `session.event` commit, which is also what clients should render from; the engine's `goal_updated` stream event duplicates it |
| `agent.runs` | `{known?: [{session, run_id?, submission_id?}]}` — each selector must carry a run or submission id; `{}` remains valid | `{runs: […], settled: […]}` — every in-flight run's `agent.started` params plus selector-matched `{run_id, session, submission_id?, status, exit_code?, durable_sequence?}` lifecycle settlements. Normal Terminal-backed statuses are immediately replayable; abnormal statuses appear only with an exact durable sequence. Active and settled state are captured atomically |

Notifications:

| method | params |
|---|---|
| `agent.started` | `{run_id, task, submission_id?, session, engine, model, max_steps, cwd?, session_root?}` — `cwd` and `session_root` are host-derived placement facts, never client-selected paths. `task` is kept for old clients that synthesize the prompt bubble from it; current clients take the bubble from the prompt's own `session.event` commit |
| `agent.event` | `{run_id?, session, event: {…}}` — the engine's event object (`assistant_delta`, `tool_result`, `agent_finished`, …); for a correlated steer receipt the host adds its optional `submission_id`. `run_id` is absent for events emitted before any run of the engine process's lifetime (a compaction on a freshly spawned engine), which route by `session` |
| `agent.error` | `{message, run_id?, exit_code?, diagnostics?}` |
| `agent.finished` | `{run_id, status, answer?, exit_code?, durable_sequence?}` — `durable_sequence` is present when an abnormal process exit's follower final scan completed before lifecycle publication; it is the exact stored boundary even when the dead turn appended no Terminal |
| `agent.durable` | `{run_id, session, sequence}` — strengthens an already-emitted failure/abort result after the host retires that serve process and its follower final scan succeeds. In particular, `agent_setup_failed`, `turn_failed`, and `agent_aborted` do not by themselves prove their best-effort Terminal append succeeded. This is a boundary update, not a second finish |

### session.*

| method | params | result |
|---|---|---|
| `session.list` | `{}` | the session index |
| `session.load` | `{session, workspace?}` — a non-blank workspace must still be registered; omitted/blank locates the session across registered stores, then the global store | `{session: <the durable session JSON>, watermark?}` — current hosts include `watermark`, the highest event `sequence` the snapshot contains (0 for an empty record); older hosts omit it, and clients derive the same value from the stored events' own sequences |
| `session.list_archived` | `{}` | the archived index |
| `session.archive` | `{session, force?}` | success returns the archived session index (the legacy `{groups}` shape) and moves the conversation plus every sibling `<session>-sr-N` descendant transcript as one family. A dirty checkout returns `{kind:"needs_force", worktree, dirty_paths, dirty_path_count}` without changing durable state; `dirty_paths` previews up to 8 paths and `dirty_path_count` counts all status rows. Clients show a discard-confirmation dialog and retry with `force` only after explicit confirmation. On success the conversation's checkout goes with it, but its name/branch/session placement remains registered (the branch survives; a `worktree.changed` broadcast reports `present: false`). "Dirty" means tracked modifications or non-ignored untracked files; ignored files count as disposable and are removed with the checkout, matching `git worktree remove`'s own semantics |
| `session.unarchive` | `{session}` | outcome — restores the conversation and every archived subagent descendant record together. A retained worktree placement whose checkout was removed returns as missing, so clients offer Repair before any agent, terminal, or file operation can continue |

Notifications:

| method | params |
|---|---|
| `session.event` | `{session, sequence, event: {sequence, ts, item}}` — one durably **committed** store event, `event` verbatim as `session.load` carries it in `events`; see *The durable transcript* below |
| `session.changed` | `{change: "archived" \| "unarchived", session}` — broadcast to every client (the requester included) when a record moves between the live and archived stores; a family archive/restore emits one fact for the parent and each descendant subagent record. Recipients apply each per-session fact immediately, keep it authoritative over already-in-flight unversioned list replies, and re-read both lists. A new connection starts a fresh list round. |

#### The durable transcript: snapshots + commits

A conversation's durable transcript has exactly two sources: the
`session.load` snapshot and the `session.event` commits that follow it. A
commit exists **if and only if** its item is in the session's durable
record, and `sequence` is the item's one-based position there — contiguous
per session. Everything else on the wire is transient stream or lifecycle
state: commit-aware clients may show deltas live, but full semantic messages,
`agent.started`'s `task`, and steer receipts never append transcript items —
their durable form arrives as a commit. A remote WebSocket receives the
lightweight forms described above instead of duplicate full semantic payloads.

Client algorithm, per session: keep a watermark `W`, starting at the
snapshot's. For each `session.event`: `sequence ≤ W` → drop (re-broadcasts
and load/commit races are harmless by construction); `sequence == W + 1` →
apply and advance; `sequence > W + 1` → a gap (missed broadcasts — a slow
client kicked, a host restart, an external CLI writer): re-read via
`session.load`, buffering commits that arrive meanwhile, and reconcile them
against the new snapshot's watermark.

The host broadcasts commits while it manages a live writer for the session
(an engine process, spawn to exit — the exit is preceded by a final sweep of
whatever the engine persisted last). Between engines nothing writes on the
host's behalf, so there is nothing to broadcast; anything an *external*
writer (the CLI sharing the session) appends meanwhile surfaces as a gap on
the next commit, which the reload answers. Compaction appends its durable
summary to the log; existing sequences never renumber, so the summary's
commit still applies contiguously.

The final sweep also closes the lifecycle proof for an abnormal exit. If the
sweep itself fails, the host keeps that run's pending durable boundary with
the retryable follower generation; a later lifecycle drain publishes the
same `agent.durable` boundary before retiring it. The targeted `agent.runs`
settlement then lets a reconnecting owner distinguish “some commits exist”
from the exact-zero case, where its recovery copy of the input is restored
for resubmission.

Old clients ignore `session.event` and keep building the transcript from
`agent.event` as before. Old hosts never send `session.event`, ignore the
capability notification, and omit the top-level `session.load.watermark`.
A new client derives the watermark from the snapshot events' own `sequence`
fields and performs one generation-tagged background `session.load` when a
named run reaches `agent.finished`. That post-terminal snapshot is the
compatibility/final-consistency path for the full semantic items the new
client deliberately does not append from `agent.event`. If an older snapshot
is already in flight, the client keeps reads single-flight and schedules one
fresh generation after it settles; commits received from a new host remain
buffered and are filtered against the resulting watermark as usual.
Only completion, context-yield, and max-step statuses prove that the semantic
log followed a successful Terminal append. Failure and abort statuses remain
unanchored until an exact durable boundary arrives, either live through
`agent.durable` or in the matching `agent.runs` settlement, so a later run's
anonymous Terminal cannot be mistaken for theirs.

Likewise, an old host's `agent.started` has no `submission_id`. The exact
`agent.start` response still carries the request's run id, so a client may use
that response to settle its local submission after the id-less Started push
has opened the same run.

### settings.* — the host-owned engine endpoint settings

The server selection and its credentials live on the **host**
(`engine-settings.json` in its runtime dir, versioned, 0600) — never in a
client. Clients edit them here and consume them as status; key
material never travels down the wire, only presence. Runs read the store
at config time, so a change replaces the conversation's engine process on
its next start.

`provider` is the one **server selection**: it decides the
chat-completions endpoint, the update channel `update.check` should be
asked with (`openseek-staging` → `"staging"`, everything else →
`"production"`), and which relay `auth.connect` signs in to (only the
OpenSeek servers have one). Committing a switch away from a signed-in
session's server signs that session out (`auth.changed` follows).

| method | params | result |
|---|---|---|
| `settings.get` | `{}` | the status shape below |
| `settings.set` | `{provider?, custom_api_url?, deepseek_api_key?, custom_api_key?, legacy_migration?}` — absent fields stay unchanged; a present string field is trimmed and, when empty, **clears** the stored value; an unknown `provider` is refused. `legacy_migration:true` is reserved for the bundled desktop's one-time import: once any settings write has claimed the durable store, a replay is acknowledged without changing it. | the status shape below, post-write |

The status shape, also the params of every `settings.changed` notification:

```jsonc
{
  "revision": 7,                    // host-process monotonic revision
  "provider": "openseek" | "openseek-staging" | "deepseek" | "custom",
  "custom_api_url": "https://…",   // absent when unset
  "has_deepseek_key": false,       // presence only — the key text never leaves the host
  "has_custom_key": false
}
```

Successful writes are serialized and increment `revision` before the status
is returned and broadcast. Clients ignore a lower revision within one host
connection generation. `BridgeReady` starts a new generation and resets that
comparison because the host process may have restarted its counter.

Notification:

| method | params |
|---|---|
| `settings.changed` | the status shape — broadcast to every client (the requester included) after each successful `settings.set`, so every page renders the same configuration |

### workspace.*

| method | params | result |
|---|---|---|
| `workspace.list` | `{}` | `{workspaces: […]}` |
| `workspace.add` | `{path}` | the updated list |
| `workspace.remove` | `{path}` | the updated list — refused while any conversation operation is still being prepared, or while a run/compaction in that workspace is active; idle engines and their final follower scan are drained before the registry entry is committed |

Notifications:

| method | params |
|---|---|
| `workspace.changed` | `{workspaces: […]}` — the canonical post-commit registry list, broadcast to every client while the host still holds its registry serialization lock; recipients invalidate older `workspace.list` replies before adopting it |

Removing a workspace only hides its registry entry; it does not delete the
directory or sessions. Clients keep the workspace attached to already-open
conversation state, so a stale attempt names that now-unregistered path and
is rejected instead of silently relocating the session into the global store.

That workspace hint is part of a client's resume state. A protocol client
that persists a workspace session across a host restart must persist and send
its `workspace` too: once the workspace is no longer registered, an omitted
hint leaves a missing id indistinguishable from a brand-new scratch session.
The current wire has no persistent detached-session tombstone; the bundled
client retains the hint and therefore gets the intended rejection.

### worktree.*

Worktrees of a registered workspace: isolated checkouts at
`<workspace>/.worktrees/<name>` on a fresh branch
`openseek/<name>` — a conversation's execution environment, bound 1:1: one
worktree belongs to exactly one conversation (and a conversation runs in at
most one worktree), while its durable history stays in the workspace's own
store.

| method | params | result |
|---|---|---|
| `worktree.list` | `{workspace}` | `{worktrees: [{name, branch, base, session?, path, present}]}` — read-only; `session` is the bound conversation, recorded at creation; a checkout deleted outside the app reports `present: false` |
| `worktree.create` | `{workspace, session}` | `{name, worktrees: […]}` — creation IS the binding: the worktree belongs to `session` from birth, and the session doubles as the idempotency key, so retrying a lost reply returns the existing binding instead of a second checkout. The session must be genuinely NEW — durable history in any store, a binding in any workspace's registry, or an in-flight first turn all refuse. The workspace must be the repository's toplevel — a repository-subdirectory workspace refuses worktrees. The host generates the name (`wt-N`, the smallest free across the registry, the `.worktrees` directory, and `openseek/*` branches); clients never name worktrees. Serialized with workspace detachment |
| `worktree.remove` | `{workspace, name, force?}` | the updated list — refused while the bound conversation's operation or run is active, and on uncommitted changes unless `force`; the branch always survives. A registry entry whose checkout is already gone is pruned. The bundled UI never calls this — archiving the conversation is how a worktree ends — but the op remains for protocol clients and orphan cleanup |

Notifications:

| method | params |
|---|---|
| `worktree.changed` | `{workspace, worktrees: […]}` — the authoritative list for that workspace, broadcast to every client after create/remove registry commits and after Archive removes a retained placement's checkout |

### git.*

| method | params | result |
|---|---|---|
| `git.branch` | `{session, cwd?, base_hint?}` | `{branch?, diffstat?}` — the checked-out branch of the conversation's working directory (detached HEAD reads as its short hash), and the branch's whole line delta. `base_hint` is the branch this work merges into: the host measures from `origin/<base_hint>` when that ref exists, otherwise from `origin/HEAD`, and clients that know a pull request's base send it because nothing local can derive one. `diffstat` is `{added, removed, files, base?, partial}`, measured from where the branch left that ref all the way to the working tree — committed and uncommitted alike, untracked files included. `base` names the ref actually measured from and is absent when the repository offered none, leaving the count to cover uncommitted work alone; `partial` marks a count that stopped short of every untracked file, so it reads as a floor rather than a total. Both fields are absent when the directory is not a git repository or git is unavailable, and `diffstat` alone is absent when the diff itself failed |
| `git.pull_request` | `{session, cwd?}` | `{pull_request?, compare_url?, branch?}` — what GitHub says about the branch that working directory has checked out, read through the user's own `gh` CLI. No `gh`, no authentication, no GitHub remote, and a detached HEAD all answer with nothing rather than an error. `branch` is the branch the host read from `HEAD`, so a checkout that moved mid-request is detectable. `pull_request` is `{number, title, state, draft, url, base, additions, deletions, changed_files, checks?}`, where `base` is the branch it merges into (the exact value for `git.branch`'s `base_hint`) and `checks` is `{passed, failed, pending}` over the head commit's rollup. `compare_url` is offered instead, for a branch with no pull request that the resolved repository already has |

### fs.* — absolute file access

Filesystem requests name their concrete absolute resource paths directly;
they carry neither a conversation id nor a workspace hint. `fs.browse` keeps
its picker-specific starting-point behavior.

| method | params | result |
|---|---|---|
| `fs.read_file` | `{path}` (absolute) | `{kind: "content", content, absolute, sig}` \| `{kind: "binary"}` \| `{kind: "oversized"}` |
| `fs.read_directory` | `{path}` (absolute directory) | `{entries: [{name, is_dir}]}`, directories first |
| `fs.search_files` | `{path, cache_key, query, max_results, generation}` (`path` absolute root) | `{files: […], from_cache, limit_hit, cancelled}` — VS Code-style cache-session query returning root-relative paths; `max_results: 0` populates without returning rows, Quick Open requests at most 512 |
| `fs.cancel_search_files` | `{cache_key, generation}` | `{}` — cancels one query while allowing cache population to finish |
| `fs.clear_file_search_cache` | `{cache_key}` | `{}` — retires one search cache session and its outstanding work |
| `fs.stat_files` | `{paths}` (absolute) | `{stats: [{path, sig}]}` — each `path` echoes its absolute input; `sig` is the opaque mtime signature `"{seconds}:{nanos}"`; `""` means the file is missing, retained for client compatibility |
| `fs.watch` | `{path, files?, directories?}` (`path` absolute) | `{}` — replaces the connection's single watcher; `files` and `directories` are relative to `path`, and each directory keeps its immediate children observable |
| `fs.unwatch` | `{}` | `{}` — stops watching when the panel is closed and it has no open tabs |
| `fs.browse` | `{path?}` (absent = home; leading `~` expands) | `{path, parent?, entries}` — subdirectory names, sorted, dotfiles skipped |

Notification:

| method | params |
|---|---|
| `fs.changed` | `{root, baseline, events: [{kind, path, old_path?}]}` — `root` is absolute; `baseline=true` follows watcher attachment; later batches use `modify` / `create` / `remove` / `rename` events with root-relative paths |
| `fs.watch_failed` | `{root, message}` — the accepted watcher could not attach or later stopped; clients fence the failure by absolute root |

`files` and `directories` are optional only for compatibility with older
clients. When both are absent the host retains the previous pruned recursive
watch; current clients always send both arrays, including empty arrays. A
watcher replacement emits a baseline after it has scanned the selected paths,
so the client can reconcile changes that raced the replacement.

### terminal.* — connection-scoped PTYs

Each client connection owns an independent set of PTYs. Terminal ids are
unique only within that connection, output returns only to that connection,
and closing the desktop page or browser WebSocket tears down all of its PTYs.
A reconnect therefore starts with no terminal sessions; clients must discard
their old ids and open replacements after `BridgeReady`.

PTY bytes stay byte-transparent over JSON. Output is always base64. Text input
uses `data`; byte-oriented xterm input uses `data_base64`, and exactly one of
the two fields must be present. Each output chunk occupies the host's bounded
flow-control window until the client acknowledges its `sequence`; retrying the
same acknowledgement within that connection is safe. An acknowledgement from
a dead connection must not be replayed after reconnect because the new
connection has an independent terminal-id namespace.

| method | params | result |
|---|---|---|
| `terminal.open` | `{session, workspace?, cols, rows}` — resolves the conversation's workspace on the host and creates it if this scratch session has not run yet | `{id}` |
| `terminal.input` | `{id, data}` \| `{id, data_base64}` | `{}` |
| `terminal.resize` | `{id, cols, rows}` | `{}` |
| `terminal.ack` | `{id, sequence}` | `{}` |
| `terminal.close` | `{id}` | `{}` |

Notifications:

| method | params |
|---|---|
| `terminal.output` | `{id, sequence, data}` — `data` is base64 of the raw PTY bytes |
| `terminal.exit` | `{id, code}` |

### lsp.*

| method | params | result |
|---|---|---|
| `lsp.open` | `{root, path}` (`root` absolute, `path` root-relative) | `{diagnostics}` — the file's diagnostics from a fresh `moon check` of its deepest containing module beneath `root`; other files' changes push as `lsp.diagnostics`. `diagnostics` absent = the check could not run; keep current markers |
| `lsp.hover` | `{root, path, line, character}` (`root` absolute, `path` root-relative, position 0-based) | `{value, markdown, has_range, start_line, start_character, end_line, end_character}` — empty `value` = no hover; served by `moon ide hover` |
| `lsp.workspace_symbols` | `{root, query}` (`root` absolute) | `{symbols: [{name, kind?, container?, path, range}]}` — served by `moon ide workspace-symbols`; result paths are root-relative |

Notification:

| method | params |
|---|---|
| `lsp.diagnostics` | `{root, path, diagnostics}` — `root` is absolute and `path` is root-relative; the diagnostics use the same array shape as `lsp.open`'s reply, and an empty array clears the file's markers |

### moonide.* — workspace navigation

Both methods accept an absolute source `path` plus positive, one-based `line`
and `column` numbers. The host passes those values unchanged to `moon ide
--loc`, after resolving the path to its attached workspace, and runs the
bundled `moon` from that workspace root (`moon` on `PATH` only for a bare
development host without a packaged toolchain seed). Result paths are
canonicalized for physical containment, then mapped back under the attached
workspace's lexical root so they match existing file/model identities. The
CLI's line and column values are returned unchanged; malformed or
workspace-escaping locations are omitted.

| method | params | result |
|---|---|---|
| `moonide.definition` | `{path, line, column}` (absolute path; positive 1-based position) | `{locations: [{path, start_line, start_column, end_line, end_column}]}` — absolute paths under the attached lexical workspace root, with Moon IDE's numeric ranges |
| `moonide.references` | `{path, line, column}` (absolute path; positive 1-based position) | `{locations: [{path, start_line, start_column, end_line, end_column}]}` — absolute paths under the attached lexical workspace root, with Moon IDE's numeric ranges |

### skills.*

| method | params | result |
|---|---|---|
| `skills.catalog` | `{}` | `{skills: […]}` — the registry's installable skills |
| `skills.installed` | `{}` | `{skills: […]}` — the global library's contents |
| `skills.install` | `{module_name, version, package_path?}` | `{installed}` |
| `skills.uninstall` | `{id}` | `{removed}` |

Notification:

| method | params |
|---|---|
| `skills.changed` | `{}` — broadcast after an install or uninstall commits; every client re-reads `skills.installed`, including clients that did not make the request |

### auth.* — remote-access sign-in

Desktop-window-only by client convention (same footing as `update.*`):
these drive the host's own relay registration, which a remote client has
no business operating. A browser signs in with the relay directly
(cookie), never through these ops.

| method | params | result |
|---|---|---|
| `auth.status` | `{}` | the status shape below |
| `auth.connect` | `{}` | the status shape — resolves only when the loopback flow finishes (browser round-trip included), so it can take minutes; errors are the JSON-RPC error response. While signed in it runs no browser flow (an exchange mints a new device row) and only makes sure the connector runs. Refused when the selected server has no relay (`deepseek`/`custom`) or when the environment override manages the connector |
| `auth.disconnect` | `{}` | the status shape — deletes the local token, best-effort revokes the device at the relay, and stops the connector. Refused in override mode |
| `auth.cancel` | `{}` | the status shape — aborts an in-flight `auth.connect` (whose own call then fails with "the sign-in was cancelled"); a no-op when nothing is in flight |

The status shape, also the params of every `auth.changed` notification:

```jsonc
{
  "server_url": "https://openseek-api.moonbitlang.cn",
                                 // signed in: the token's issuer; signed out: the
                                 // selection's server — absent when that server has
                                 // no relay (deepseek/custom) or in a supervisor push
  "connected": false,            // control WS currently registered
  "managed_by_env": true,        // present only under the OPENSEEK_RELAY_URL override
  "user":   {"login": "…", "avatar_url": "…"},   // absent when signed out
  "device": {"id": "d_…", "name": "…", "url": "…/console/releases/v0.1.16/index.html?device=d_…"}  // absent when signed out
}
```

Notification:

| method | params |
|---|---|
| `auth.changed` | the status shape — pushed whenever registration state moves (connector registered, dropped, token revoked, signed out) |

### update.*

Desktop-window-only by client convention: applying an update swaps the
bundle under the running process and relaunches through the window's close
path, which only exists on the in-process bridge. The host serves these on
both transports (it cannot tell clients apart), but the browser frontend
never calls them and shows no update UI.

| method | params | result |
|---|---|---|
| `update.check` | `{channel?}` (anything but `"staging"` reads as production) | `{kind: "up_to_date" \| "available" \| "unreachable" \| "malformed" \| "broken", …}` |
| `update.download` | `{channel?}` | `{accepted: true}` — starts app-lifetime download/verification work and returns without waiting for it |
| `update.apply` | `{}` | `{applied}` — the bundle swap succeeded and the window may close |

Notification:

| method | params |
|---|---|
| `update.download_progress` | `{downloaded_bytes, total_bytes}` — bytes received for the active package; `total_bytes` is a positive byte count when the response supplies a usable `Content-Length`, otherwise `null` |
| `update.downloaded` | `{version}` — the package is verified and staged; the desktop may call `update.apply` |
| `update.download_failed` | `{message}` — the background download, verification, or staging step failed |

### app.* / host.*

| method | params | result |
|---|---|---|
| `app.list` | `{}` | `{apps: [{id, name, icon}]}` — `icon` is a `data:image/png` URL, empty when extraction failed |
| `app.launch` | `{session, cwd?, app}` | `{launched}` |
| `host.open_path` | `{session, cwd?, path}` | `{opened}` — hand a transcript-referenced path to the system opener; relative paths resolve against the conversation's working directory (`cwd` when the client has it, else derived from `session`); deliberately no workspace containment — the user clicked a path the agent itself surfaced |

Reserved notification (not yet emitted over the wire):
`host.notification_clicked` `{session}` — a system notification was clicked.
On the desktop this arrives through the proton bridge; it appears here once
remote clients need it.

## Relay tunnel

The host reaches its clients by dialing out — it can live behind NAT with
nothing exposed. The relay is a **WebSocket splicer**: it pairs sockets and
forwards frames verbatim, with zero knowledge of the protocol above.

```
browser                    relay (public)                  host (desktop app)
  │                           │                                │
  │                           │◄─── ① control WS: /v1/tunnel ──┤ outbound, long-lived
  │                           │   register{device_token,name}  │
  │                           ├── registered{device:"d_…"} ───►│
  │                           │                                │
  ├─② wss://relay/v1/devices─►│                                │
  │        /d_…/ws            ├──── ③ open{stream:"s1"} ──────►│
  │   (session cookie)        │                                │
  │                           │◄── ④ data WS: /v1/tunnel/s1 ───┤ one per browser client
  │                           │                                │
  │◄════ ⑤ relay splices ② and ④ frame-for-frame ════════════►│
```

Control-channel frames (JSON text over the `/v1/tunnel` WebSocket):

| frame | direction | fields |
|---|---|---|
| `register` | host → relay | `{device_token, name}` — sent once after connecting |
| `registered` | relay → host | `{device}` — the stable public id; reconnects with the same token reuse it |
| `fail` | relay → host | `{message}` — registration rejected. A bad or revoked token is terminal: the host stops retrying, surfaces it (`auth.changed`), and waits for a new sign-in |
| `open` | relay → host | `{stream}` — a client connected to `/v1/devices/<device>/ws`; the host dials `GET /v1/tunnel/<stream>` (upgrade) back |

The data WebSocket (④) carries client protocol frames untouched. On the
host side each data connection is served by the same JSON-RPC dispatch the
bridge feeds — the host has no tunnel-specific protocol handling beyond the
four control frames. Either side closing a spliced socket closes its twin;
a dropped control connection closes every stream of that device.

The relay serves the frontend bundle itself, at `/` (sign-in + the
multi-device console; the bundle never crosses the tunnel). Nothing else
is tunneled: the client protocol has exactly one entry point, the
WebSocket.

## Changes from v1

The retired v1 design embedded an HTTP + SSE gateway in the desktop. What
changed and why:

- **The host process runs no server.** v1 embedded an HTTP gateway in the
  desktop and pointed the window at `http://127.0.0.1:<port>/`. v2 keeps
  the original desktop architecture — window on `proton://app/`, in-process
  bridge — and adds remote access as a pure outbound feature: dial the
  relay, register, serve each spliced WebSocket. No port, no static file
  server, no CORS, and the window regains bridge-only capabilities
  (notification-click focus).
- **One transport for the wire instead of three.** v1 ran fetch for
  commands, SSE for events, and a bespoke HTTP-over-WebSocket frame
  protocol (`req`/`resp`/`chunk`/`end`/`abort`) inside the tunnel. v2 is
  one JSON-RPC WebSocket, and the tunnel forwards it blind.
- **No connection seq / replay ring / sticky starts.** v1 resumed event streams by
  cursor (`?since=`) against a 4096-frame ring, with in-flight runs'
  `started` frames pinned. v2 reconnects by resyncing state: the serve
  engine appends every completed item to the session store as it runs, so
  `session.load` rebuilds the durable transcript, while `agent.runs` returns
  current starts plus selector-targeted process-lifetime settlements needed
  to close exact reconnect ownership (including a zero-commit abnormal exit).
  Full-message events overwrite partial deltas within one step.
- **Route/op names unified** under dotted namespaces (`agent.*`,
  `session.*`, `workspace.*`, `git.*`, `fs.*`, `lsp.*`, `moonide.*`, `skills.*`,
  `update.*`, `app.*`, `host.*`), shared verbatim by the bridge and the
  WebSocket.
- **Most in-band sentinels were removed from the wire**: request `cwd` and
  reply `branch` are optional fields instead of `""`; the missing-file
  `sig: ""` reply remains for client compatibility. Stopping the watcher is `fs.unwatch`
  instead of a sentinel `fs.watch`; `host.meta` carries no
  `capabilities` list (the method catalog is the capability surface).
- **Device ids stopped being capabilities** (v2.1): originally the
  unguessable device id was the only barrier, minted per token by the
  relay. With the user system (see Authentication) the id is a stable
  public identifier, ownership is enforced at the relay, APIs moved under
  `/v1`, and the browser WS left the page namespace
  (`/d/<device>/api/v1/ws` → `/v1/devices/<device>/ws`).
