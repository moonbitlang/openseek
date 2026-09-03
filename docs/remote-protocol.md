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
delivered by `session.event`. Every Desktop API run names a durable session, so
the pushed `agent.started` carries lifecycle identity only;
`reasoning_message` and `assistant_message` remain as stream-settlement signals
with `content: ""`; `tool_result`, `auto_compaction_finished`, `agent_finished`,
and `context_yield` are omitted. The separate `agent.finished` lifecycle
notification remains, including its optional `answer`;
`compaction_finished` remains with an empty `summary` so it still closes the
lifecycle state. Deltas — including the `reasoning_delta` progress stream —
usage, step progress, tool-decode errors, runtime status, steer
receipts, and all other run/compaction lifecycle and error events are unchanged.
Before publishing a new `agent_step` or a successful terminal lifecycle event,
the Desktop host drains that session's serialized follower. Consequently every
durable commit preceding the boundary reaches both local and remote clients
first; live reasoning can hand off without a follower race.
The desktop's in-process bridge continues to receive the hub's complete stream;
this trimming is specific to remote WebSocket delivery.

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
transient notifications. (The one sequence that exists is per durable record
— a store-qualified session — and durable, not per-connection:
`session.event` carries the store's own event sequence — see *The durable
transcript* below — and a reconnect recovers missed commits by re-reading,
never by replay.) The sole lifecycle exception is `agent.runs`'s targeted,
process-lifetime settlement state for owners the reconnecting client names;
it is a state query, not an event log. A connection delivers events from the
moment it exists; whatever a client missed while disconnected it recovers by
re-reading state:

1. Connect the WebSocket. The host sends `agent.connected` as the connection's
   first notification — `{stage}`, where `stage` is `"accepted"` (the
   transport took this client; the engine pump may still be between
   generations) or `"serving"` (the pump entered a serving generation and
   accepts runs). Both mean the same thing to a client: re-read your state.
   Every conversation belongs to a registered workspace, so a broadcast store
   root names its own project (`<project>/.openseek`) and needs no anchor
   value here. The host then starts forwarding the remote delivery stream.
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
   accepted under the same owner gate, whatever its status. One
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
its targeted `agent.runs` settlement supplies the lifecycle outcome. A run
that recorded nothing loads as an empty transcript rather than a failure, so
"nothing was committed" needs no separate proof. Settlements live only for the
host process lifetime, so after a restart a pre-restart submission has no
lifecycle settlement to look up. It is not therefore unresolvable: the record
outlives the host, so `session.load` shows whether the prompt landed. The
host does not deduplicate a resent prompt, so a client that resends one it
could not confirm risks a second copy of the text; read the record first.

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
absence as `""`, `0`, or another in-band sentinel, on either side.

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
the User item reached the store; the durable proof is the `session.event`
commit carrying that `submission_id` on its `User` item, which is what a
client should settle its draft on.

This is lifecycle correlation only; durable transcript items still come from
`session.event`. Old clients omit it, and old hosts omit the echoes.

| method | params | result |
|---|---|---|
| `agent.start` | `{task, session, submission_id?, model?, thinking?, max_steps?, workspace?}` — `session` is a required non-blank durable conversation id. `thinking`, when present, is `no`, `high`, or `max`. No credentials or store path are accepted: the host resolves settings and durable placement; `workspace` is honored only when registered. A session bound to one of the workspace's worktrees (`worktree.create` binds at creation) runs in that checkout — the start never names or mutates worktrees | `{run_id, status, …}` — `accepted` after the complete prompt command is written; a post-`started` write failure returns `failed`, while pre-`started` failures use the error response. Every reply that returns names the run it opened; the host does not deduplicate a resent `submission_id` |
| `agent.cancel` | `{run_id?}` (absent = the latest run) | `{run_id?}` — the run the cancellation reached, absent when no turn was open. Absence is an answer, not a failure: a Stop racing a turn that just ended wanted the run over, and it is. The call fails only when the cancellation could not be delivered, which means the turn is still running and nobody asked it to stop. Delivery is not the end of the turn — the run ends through its own `agent.finished` |
| `agent.steer` | `{text, run_id?, submission_id?}` | steer outcome |
| `agent.compact` | `{session, model?, thinking?, max_steps?, workspace?}` — `agent.start` minus `task`: a conversation resumed after a restart has no live process, and compacting spawns one with these settings | compaction outcome |
| `agent.goal` | `{session, text?, auto?, model?, thinking?, max_steps?, workspace?}` — sets the session's standing goal to `text`, or clears it when `text` is absent; the engine settings match `agent.compact`'s, and a blank `session` is refused before engine lookup. `auto` arms the engine's autonomous continuation and is **currently rejected**: serve announces the turns it starts with `goal_continue`, which this host does not yet fold into a run's lifecycle, so an autonomous turn would leave the engine looking idle to `agent.start` | `{delivered}` — delivery, not durability: the command reached a live engine's stdin. The goal itself is confirmed by the `[goal]` / `[goal cleared]` runtime-notice arriving as a `session.event` commit, which is also what clients should render from; the engine's `goal_updated` stream event duplicates it |
| `agent.runs` | `{known?: [{session, run_id?, submission_id?}]}` — each selector must carry a run or submission id; `{}` remains valid | `{runs: […], settled: […]}` — every in-flight run's `agent.started` params plus selector-matched `{run_id, session, submission_id?, status, exit_code?}` lifecycle settlements. Every settlement a selector names is replayed, whatever its status: how much the run committed is a question the transcript read answers. Active and settled state are captured atomically |

All three engine-spawning requests use the same `thinking` setting. A present
value overrides `OPENSEEK_THINKING`; an older client that omits it inherits
that environment value and then the `max` default. The setting is part of the
host's process identity, so changing it replaces an idle process rather than
silently continuing with the previous reasoning mode.

Notifications:

| method | params |
|---|---|
| `agent.started` | `{run_id, submission_id?, session, engine, model, max_steps, session_root?}` — `session_root` is a host-derived durable-store fact, never a client-selected path; the prompt bubble comes from its own `session.event` commit |
| `agent.event` | `{run_id?, session, event: {…}}` — the engine's event object (`assistant_delta`, `tool_result`, `agent_finished`, …); for a correlated steer receipt the host adds its optional `submission_id`. `run_id` is absent for events emitted before any run of the engine process's lifetime (a compaction on a freshly spawned engine), which route by `session` |
| `agent.error` | `{message, run_id?, exit_code?, diagnostics?}` |
| `agent.finished` | `{run_id, status, answer?, exit_code?}` — the run's outcome, published when the engine's stdout event that ends the turn arrives, or at the engine's death for a turn whose event never came (`failed`). The durable record renders the conversation and never settles a run: the two travel independently, so a client may see this before, after, or without the matching `session.event` commit |

### session.*

| method | params | result |
|---|---|---|
| `session.list` | `{}` | the session index |
| `session.load` | `{session, workspace?}` — a non-blank workspace must still be registered; omitted/blank locates the session across registered stores, then the global store | `{session: <the durable session JSON>, watermark?}` — current hosts include `watermark`, the highest event `sequence` the snapshot contains (0 for an empty record); older hosts may omit it, in which case clients derive it from the stored events' own sequences. |
| `session.load_archived` | `{session, workspace?}` — the same store selection rules as `session.load`, but reads only from that store's archived twin | `{session: <the durable session JSON>, watermark?}` without restoring or otherwise changing the archived record |
| `session.list_archived` | `{}` | the archived index |
| `session.rename` | `{session, workspace, title}` — all fields are required; `workspace` must name the registered store that owns the live record, and `title` must be non-blank | `{}` — atomically writes display metadata beside the append-only transcript, so a running conversation can be renamed without rewriting its history |
| `session.archive` | `{session, force?}` | success returns the archived session index (the legacy `{groups}` shape) and moves the conversation plus every sibling `<session>-sr-N` descendant transcript as one family. A dirty checkout returns `{kind:"needs_force", worktree, dirty_paths, dirty_path_count}` without changing durable state; `dirty_paths` previews up to 8 paths and `dirty_path_count` counts all status rows. Clients show a discard-confirmation dialog and retry with `force` only after explicit confirmation. On success the conversation's checkout goes with it, but its name/branch/session placement remains registered (the branch survives; a `worktree.changed` broadcast reports `present: false`). "Dirty" means tracked modifications or non-ignored untracked files; ignored files count as disposable and are removed with the checkout, matching `git worktree remove`'s own semantics |
| `session.unarchive` | `{session}` | outcome — restores the conversation and every archived subagent descendant record together. A retained worktree placement whose checkout was removed returns as missing, so clients offer Repair before any agent, terminal, or file operation can continue |
| `session.delete_archived` | `{session, workspace}` | permanently deletes the archived conversation record from the exact host-listed project store and every archived subagent descendant record in that store, then returns the archived index. Its retained worktree placement is removed and broadcast, but project files and the Git branch remain. The operation refuses unknown stores, live records, and running/compacting family members |

Notifications:

| method | params |
|---|---|
| `session.event` | `{session, sequence, session_root, event: {sequence, ts, item}}` — one durably **committed** store event, `event` verbatim as `session.load` carries it in `events`. `session_root` is the durable store root the commit was read from: session ids are not globally unique across stores, so the durable identity is `(session_root, session)` and a client must never merge same-id records from different stores; see *The durable transcript* below |
| `session.changed` | `{change: "archived" \| "unarchived" \| "deleted" \| "renamed", session, workspace}` — broadcast to every client (the requester included) when a record moves between stores, is permanently deleted, or changes display title; `workspace` is the owning project path, so same-ID records in other project stores remain untouched. A family operation emits one fact for the parent and each descendant subagent record. Recipients apply each store-qualified fact immediately, keep placement facts authoritative over already-in-flight unversioned list replies, and re-read both lists. A new connection starts a fresh list round. |

#### The durable transcript: snapshots + commits

A conversation's durable transcript has exactly two sources: the
`session.load` snapshot and the `session.event` commits that follow it. A
commit exists **if and only if** its item is in the session's durable
record, and `sequence` is the item's one-based position there — contiguous
per store-qualified session. Everything else on the wire is transient stream
or lifecycle
state: commit-aware clients may show deltas live, but full semantic messages,
transient lifecycle notifications, and steer receipts never append transcript
items — their durable form arrives as a commit. A remote WebSocket receives
the lightweight forms described above instead of duplicate full semantic
payloads.

Client algorithm, per store-qualified session — the `(session_root, session)`
pair, since one id may hold independent records in two project stores at
once: keep a watermark `W`, starting at the
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

If the final sweep itself fails, the follower stays installed and a later
lifecycle drain — a replacement spawn, an archive, a detach — retries it. The
run is still reported as finished; what the conversation holds is learned by
reading it, and a record that was never created reads as an empty one.

Old clients ignore `session.event` and keep building the transcript from
`agent.event` as before. Old hosts never send `session.event`, ignore the
capability notification, and omit the top-level `session.load.watermark`.
A separate generation of hosts predates the store-qualified contract: such
a host omits `session_root` from both `agent.connected` and `session.event`.
The bundled client does not interoperate with them (the desktop frontend and
host ship in lockstep — a rootless `agent.connected` never reaches readiness
and a rootless commit is dropped as malformed); a third-party client that
chooses to accept them falls back to id-only identity, knowing same-id
records from different stores become indistinguishable.
A new client derives the watermark from the snapshot events' own `sequence`
fields and performs one generation-tagged background `session.load` when a
named run reaches `agent.finished`. That post-terminal snapshot is the
compatibility/final-consistency path for the full semantic items the new
client deliberately does not append from `agent.event`. If an older snapshot
is already in flight, the client keeps reads single-flight and schedules one
fresh generation after it settles; commits received from a new host remain
buffered and are filtered against the resulting watermark as usual.
Only completion, context-yield, and max-step statuses prove that the semantic
log followed a successful Terminal append; failure and abort statuses are
written from a catch block whose append may itself have failed. A client
infers nothing from that: the host attributes a recorded Terminal to the run
that was open when it read it, and the snapshot read reports what the record
actually holds.

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

`provider` is the chat endpoint selection: `deepseek` (the official
endpoint with the user's key), `glm` (the official Z.AI GLM endpoint
with its own key), or `custom` (any OpenAI-compatible
chat-completions URL; key optional). SeekMoon runs are
bring-your-own-key only — the hosted proxy is retired, and the retired
names `openseek` / `openseek-staging` are accepted aliases that resolve
to `deepseek`. The update channel is always `production` and remote
access always targets the SeekMoon relay origin: both live on the
SeekMoon origin independently of the chat provider. A settings commit
still signs out a session whose issuer no longer matches the origin.

| method | params | result |
|---|---|---|
| `settings.get` | `{}` | the status shape below |
| `settings.set` | `{provider?, custom_api_url?, deepseek_api_key?, glm_api_key?, custom_api_key?, legacy_migration?}` — absent fields stay unchanged; a present string field is trimmed and, when empty, **clears** the stored value; an unknown `provider` is refused. `legacy_migration:true` is reserved for the bundled desktop's one-time import: once any settings write has claimed the durable store, a replay is acknowledged without changing it. | the status shape below, post-write |

The status shape, also the params of every `settings.changed` notification:

```jsonc
{
  "revision": 7,                    // host-process monotonic revision
  "provider": "deepseek" | "glm" | "custom",
  "custom_api_url": "https://…",   // absent when unset
  "has_deepseek_key": false,       // presence only — the key text never leaves the host
  "has_glm_key": false,
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
| `workspace.settings_get` | `{workspace}` | `{workspace, worktree_mode}` — the workspace's desktop-owned settings (`<workspace>/.openseek/settings.json`); `worktree_mode` says whether a NEW conversation starts in a fresh bound git worktree instead of the workspace root, and a missing file or field reads as the Local default (`false`). Only a registered workspace may be read |
| `workspace.settings_set` | `{workspace, worktree_mode}` | the committed `{workspace, worktree_mode}` — the write and its broadcast are one serialized commit; unknown fields a newer build stored in the file survive the rewrite |

Notifications:

| method | params |
|---|---|
| `workspace.changed` | `{workspaces: […]}` — the canonical post-commit registry list, broadcast to every client while the host still holds its registry serialization lock; recipients invalidate older `workspace.list` replies before adopting it |
| `workspace.settings_changed` | `{workspace, worktree_mode}` — one workspace's committed settings, broadcast to every client (the requester included) after each successful `workspace.settings_set`; recipients invalidate older `workspace.settings_get` replies for that workspace before adopting it |

Removing a workspace only hides its registry entry; it does not delete the
directory or sessions. Clients keep the workspace attached to already-open
conversation state, so a stale attempt names that now-unregistered path and
is rejected instead of silently relocating the session into the global store.

That workspace hint is part of a client's resume state. A protocol client
that persists a workspace session across a host restart must persist and send
its `workspace` too: once the workspace is no longer registered, an omitted
hint leaves a missing id indistinguishable from a brand-new session.
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

### fs.* — host file access

Filesystem requests normally name their concrete absolute resource paths
directly. `fs.read_file` also accepts an explicit absolute `root` paired with a
relative `path`; it carries no conversation id. `fs.browse` keeps its
picker-specific starting-point behavior.

| method | params | result |
|---|---|---|
| `fs.read_file` | `{path, root?}` (`path` is absolute without `root`; otherwise `root` is absolute and `path` is relative to it) | `{kind: "content", content, absolute, sig}` \| `{kind: "binary_content", data_base64, media_type}` \| `{kind: "binary"}` \| `{kind: "oversized"}` |
| `fs.read_directory` | `{path}` (absolute directory) | `{entries: [{name, is_dir}]}`, directories first |
| `fs.search_files` | `{path, cache_key, query, max_results, generation}` (`path` absolute root) | `{files: […], from_cache, limit_hit, cancelled}` — VS Code-style cache-session query returning root-relative paths; `max_results: 0` populates without returning rows, Quick Open requests at most 512 |
| `fs.cancel_search_files` | `{cache_key, generation}` | `{}` — cancels one query while allowing cache population to finish |
| `fs.clear_file_search_cache` | `{cache_key}` | `{}` — retires one search cache session and its outstanding work |
| `fs.search_text` | `{root, query, regex, case_sensitive, whole_word, include_glob, exclude_glob, session_key, generation, max_results}` (`root` absolute; include/exclude are comma-separated VS Code-style globs) | `{root, generation, matches: [{path, line_number, preview, preview_start_column, ranges: [{start_column, end_column}]}], match_count, file_count, limit_hit, cancelled, error_code?, error_message?}` — bounded workspace grep using bundled ripgrep; paths are root-relative, line/preview columns and exclusive range ends are one-based UTF-16. Success omits both error fields; failures include both, and `error_code` distinguishes `invalid_regex`, `invalid_glob`, `permission_denied`, `rg_unavailable`, `invalid_request`, and `search_failed` |
| `fs.cancel_search_text` | `{session_key, generation}` | `{}` — cancels that generation and records a bounded recent monotonic cancellation frontier; a newer generation in the same session automatically cancels its predecessor |
| `fs.stat_files` | `{paths}` (absolute) | `{stats: [{path, signature}]}` — each `path` echoes its absolute input; `signature` is `{kind: "present", sig}` with the opaque mtime signature `"{seconds}:{nanos}"`, `{kind: "missing"}` when the path no longer resolves to a file, or `{kind: "failed", message}` for any other stat error |
| `fs.watch` | `{path, files, directories, recursive?, generation}` (`path` absolute; `generation` string) | `{}` — replaces the connection's single watcher; success means the native watcher has scanned its initial tree and emitted its baseline, while setup failure rejects this request; `files` and `directories` are relative to `path`, each directory keeps its immediate children observable, `recursive=true` additionally watches every non-pruned descendant, and clients use a page-unique namespace plus a monotonically increasing counter for `generation` |
| `fs.unwatch` | `{}` | `{}` — stops watching when the panel is closed and it has no open tabs |
| `fs.browse` | `{path?}` (absent = home; leading `~` expands) | `{path, parent?, entries}` — subdirectory names, sorted, dotfiles skipped |

Notification:

| method | params |
|---|---|
| `fs.changed` | `{root, baseline, events: [{kind, path, old_path?}], generation}` — `root` is absolute; `baseline=true` follows watcher attachment; later batches use `modify` / `create` / `remove` / `rename` events with root-relative paths; the string `generation` echoes the owning `fs.watch` request |
| `fs.watch_failed` | `{root, message, generation}` — a watcher stopped after its `fs.watch` request had successfully activated it; setup failures reject `fs.watch` directly, and the string `generation` keeps a delayed runtime failure from attaching to a replacement or reloaded page |

The path arrays are always present, including when empty. A watcher replacement
emits a baseline after it has scanned the selected paths and before its request
returns, so the client can reconcile changes that raced the replacement.

Text search mirrors VS Code's default ripgrep contract: it follows local
`.gitignore`, `.ignore`, and `.rgignore` files without inheriting parent or
global ignore files, includes hidden source files, follows symlinks, ignores
`RIPGREP_CONFIG_PATH`, matches globs and ignore files case-insensitively outside
Linux, and skips binary or files larger than 16 GiB. Directory
exclusions start with VS Code's default `files.exclude` and `search.exclude`
globs. Like the Search view, comma-separated patterns are split outside `{...}`
and `[...]`; an ordinary `src` entry expands to both `**/src` and `**/src/**`,
`.mbt` expands as `*.mbt`, and `./src` stays relative to the selected root.
The protocol is intentionally single-root: `../`, `~/`, and absolute search
locations are rejected instead of escaping `root`. Includes are emitted first
and every default or request exclusion follows, so an exclusion wins when both
match. The Host accepts at most 20,000 occurrences and sets `limit_hit` when the
cap is reached. A connection teardown cancels every process it owns. Installed
builds resolve only their packaged ripgrep; a `PATH` fallback is permitted
solely for a detected development layout.

### terminal.* — connection-scoped PTYs

Each client connection owns an independent set of PTYs. Terminal ids are
unique only within that connection, output returns only to that connection,
and closing the desktop page or browser WebSocket tears down all of its PTYs.
A reconnect therefore starts with no terminal sessions; clients must discard
their old ids and open replacements after `BridgeReady`.

PTY bytes stay byte-transparent over JSON. Output is always base64. Text input
uses `data`; byte-oriented xterm input uses `data_base64`, and exactly one of
the two fields must be present. Each output chunk occupies the host's bounded
flow-control window until the client acknowledges it. An acknowledgement for
`sequence` also acknowledges every earlier outstanding sequence for that
terminal, so a later acknowledgement covers an earlier request that did not
reach the host. Duplicate acknowledgements and sequences older than the
already-applied frontier are safe no-ops. An acknowledgement from a dead
connection must not be replayed after reconnect because the new connection
has an independent terminal-id namespace.

| method | params | result |
|---|---|---|
| `terminal.open` | `{session, workspace?, cols, rows}` — resolves the conversation's workspace on the host — a session no attached workspace owns is refused rather than given a directory | `{id}` |
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

All three methods accept the owning `session`, an absolute editor `root`, and a
source `path` relative to that root. Definition and References additionally
accept positive, one-based `line` and `column` numbers. The root is the actual
main checkout, linked worktree, or Codex cwd displayed by the editor; it need
not be an attached OpenSeek workspace. The host runs the bundled `moon` from
that root (`moon` on `PATH` only for a bare development host without a packaged
toolchain seed). Result paths are canonicalized for physical containment, then
mapped back under the supplied root's lexical spelling so they match existing
file/model identities. Navigation result lines and columns remain one-based;
CodeLens source ranges and action positions remain zero-based LSP coordinates.
Malformed, unknown, or root-escaping rows are omitted.

| method | params | result |
|---|---|---|
| `moonide.definition` | `{session, root, path, line, column}` (`root` absolute, `path` relative; positive 1-based position) | `{locations: [{path, start_line, start_column, end_line, end_column}]}` — absolute paths under the supplied lexical root, with Moon IDE's numeric ranges |
| `moonide.references` | `{session, root, path, line, column}` (`root` absolute, `path` relative; positive 1-based position) | `{locations: [{path, start_line, start_column, end_line, end_column}]}` — absolute paths under the supplied lexical root, with Moon IDE's numeric ranges |
| `moonide.codelens` | `{session, root, path}` (`root` absolute, `path` relative) | `{lenses: [{range, title, action}]}` — `range` and `action.position` use zero-based LSP coordinates. `action` is either `{kind:"local", position, locations}` with canonical one-based locations, or `{kind:"outside", position}` |

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
| `auth.connect` | `{}` | the status shape — resolves only when the loopback flow finishes (browser round-trip included), so it can take minutes; errors are the JSON-RPC error response. While signed in it runs no browser flow (an exchange mints a new device row) and only makes sure the connector runs. Refused only when the environment override manages the connector — the relay lives on the SeekMoon origin and no longer depends on the chat provider |
| `auth.disconnect` | `{}` | the status shape — deletes the local token, best-effort revokes the device at the relay, and stops the connector. Refused in override mode |
| `auth.cancel` | `{}` | the status shape — aborts an in-flight `auth.connect` (whose own call then fails with "the sign-in was cancelled"); a no-op when nothing is in flight |

The status shape, also the params of every `auth.changed` notification:

```jsonc
{
  "server_url": "https://openseek-api.moonbitlang.cn",
                                 // signed in: the token's issuer; signed out: the
                                 // SeekMoon relay origin — always present now that
                                 // the relay no longer depends on the chat provider
                                 // (absent only in a supervisor push)
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
| `update.check` | `{channel?}` (anything but `"staging"` reads as production; the desktop client always asks production — the channel no longer derives from the chat provider) | `{kind: "up_to_date" \| "available" \| "unreachable" \| "malformed" \| "broken", …}` |
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
| `host.open_path` | `{session, cwd?, path}` | `{opened, editor_target?, directory_target?, error?}` — return a viewer-sized UTF-8 text file inside the checkout as `{opened:false, editor_target:{path,line?,column?}}` for the built-in editor; hand other existing paths to the system opener as `{opened:true}`; missing paths and text files outside the checkout return a refusal as `{opened:false, error:"<reason>"}` (older hosts raised instead); an existing literal filename wins before `path:line[:column]` or `path#Lline` suffix parsing; relative input resolves against the conversation's working directory (`cwd` when present, otherwise derived from `session`) |
| `host.reveal_path` | `{session, cwd?, path}` | `{revealed, error?}` — resolve the reference exactly like `host.open_path`, including cwd fallback and position suffixes, then show the underlying file or directory in the host file manager; a refusal returns `{revealed:false, error:"<reason>"}` instead of raising |

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
