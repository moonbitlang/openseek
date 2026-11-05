# Host tools

How agents connect to capabilities contributed by a desktop host. A shared
`Dispatcher` handles JSON-RPC messages over HTTP or host-supplied stdio streams.
The engine's existing connection uses HTTP through the root module's
`mcp/streamhttp` client. The host chooses which tools to register.

It depends on async HTTP and core codecs, not on Proton, the engine, or any
package that contributes tools. Dependencies point inward: a package that owns
a capability builds `Tool` values over it, and the host constructs one
`Server` with them and hands it to `@api.ApiState`. From there the engine
actor grants every engine it starts access to the server, and
`ApiState::start_services` serves it alongside the backend's other
app-lifetime owners.

## Shape

The endpoint supports stateless MCP `2026-07-28` requests as well as legacy
initialization-based clients. Each modern request carries its version and
capabilities in `params._meta`; no prior handshake or MCP session is required.
`stateless.mbt` validates the required HTTP headers against the body before
dispatch. `server/discover` reports the modern capabilities. Legacy `initialize`
continues to negotiate `2025-11-25` and earlier supported revisions.

- `tool.mbt` — the contract a contributing package implements: `Tool` (name,
  description, input schema, handler) and `ToolCall` (the calling conversation
  and the arguments). A handler returns the `Content` blocks the agent reads,
  text or base64 images, sent as the result's `content` in order; raising makes
  the call a tool-level failure the agent also reads.
- `dispatcher.mbt` and `protocol.mbt` — the shared tool catalog and JSON-RPC
  dispatch for `initialize`, `ping`, `tools/list`, and `tools/call`, plus
  stateless `server/discover`.
- `server.mbt` — the listener, the grants, and one task per request.
- `stdio.mbt` — newline-delimited JSON-RPC over streams supplied by the host.

## Host-owned streams

`Dispatcher(tools, version~)` creates a tool catalog without binding a port.
`dispatch(message, session~, groups~)` answers one parsed JSON-RPC message,
returning `None` for a notification or response. The host supplies the
authenticated conversation and permitted tool groups. These values never come
from the message or its tool arguments. Omitting `groups` offers all tools.

An existing HTTP server exposes this same dispatcher through
`server.dispatcher()`. Tool registrations through either object are shared.
To serve a pipe pair, the host can start:

```mbt nocheck
group.spawn_bg(() => {
  server.dispatcher().serve_stdio(
    input,
    output,
    session=trusted_session,
    groups=["browser"],
  )
})
```

`input` and `output` implement `async/io.BinaryReader` and `BinaryWriter`.
The host owns their creation, authentication, closure and task lifetime.
The adapter does not claim process stdin or stdout, so a host can dedicate
pipes to MCP while retaining its application log channel. All tool handlers
continue to execute in that host process, with their existing browser and
session objects. The HTTP bearer-token grant and Origin checks still apply
to HTTP requests; stdio relies on the host's authenticated stream binding.

Each input line is a UTF-8 JSON-RPC message; each response is one JSON line.
The receive loop parses and classifies messages before scheduling. Notifications
and peer responses are ignored without starting tasks. Invalid messages are
answered directly, including a parse error for malformed JSON, and the adapter
continues with the next line. Up to 16 requests may be in flight per connection.
A request keeps its slot until its response is written, so a slow response
reader also bounds completed results waiting to be sent. At capacity, the
receive loop waits before starting another task. Response writes are serialized
so frames cannot interleave. Input EOF drains accepted requests. I/O failures,
cancellation, or an input line exceeding
the one-megabyte limit end the adapter and propagate to its owner. The caller
closes both streams. Dispatcher tool-failure diagnostics use the host's xlog
handler, as they do over HTTP. The desktop host writes these logs to
`openseek-desktop.log`. A host using process stdout for MCP must configure
xlog to write to a file or stderr before serving; xlog defaults to stdout.
The adapter writes only JSON-RPC responses to its supplied output stream.

## Configuration

Engines started by a host configured with tools connect automatically, for both
conversations and scheduled runs. The engine launcher writes `host-mcp.json`
in the runtime directory (or the global store directory when no runtime directory
was supplied) and passes it as the first `--mcp-config` argument. It contains:

```json
{
  "mcpServers": {
    "seekmoon": {
      "url": "${OPENSEEK_DESKTOP_TOOLS_URL}",
      "headers": {
        "Authorization": "Bearer ${OPENSEEK_DESKTOP_TOOLS_TOKEN}"
      }
    }
  }
}
```

OpenSeek expands the HTTP URL and header values from the engine's environment
when it loads the configuration. Missing variables are errors, so a process
that was not granted access cannot connect through this entry. The tools
reach the model as `mcp__seekmoon__<tool>` automatically.

The user's `~/.openseek/mcp.json`, or the `OPENSEEK_MCP_CONFIG` fallback when that
file is absent, follows the host defaults as another `--mcp-config` argument.
Later entries replace whole same-named servers before any connection starts.
A user can therefore override `seekmoon` to customize its headers. A broken
user file is reported without preventing the host defaults from loading.
The old `seekmoon mcp` stdio relay and executable have been removed.

To offer a subset, override the entry in `~/.openseek/mcp.json` and add `"X-SeekMoon-Tool-Groups": "browser"` to the headers.
Groups are comma-separated; a tool's group is its name before the first
underscore (or the whole name if it has none). The host applies the filter to
both `tools/list` and `tools/call`. Omitting the header offers every tool.

## Grants

A grant is two environment variables: `OPENSEEK_DESKTOP_TOOLS_URL`, where the
server is, and `OPENSEEK_DESKTOP_TOOLS_TOKEN`, a bearer token minted for one
conversation on first use and kept for the launch. `Server::grant(session)`
returns them and the engine actor sets them on every engine it starts for that
conversation — a `serve` engine and a scheduled run alike.

The token is how a handler knows who is calling: `ToolCall.session` comes from
the token, never from arguments the model wrote. Everything an engine runs
inherits its environment, so a sub-run or a background job acts for the
conversation that started it. Neither the address nor the token is written to disk;
the generated config contains only environment-variable placeholders.

A host that offers no tools removes both variables from the engines it starts,
so a grant it inherited — a host launched from another host's agent — is not
passed on.

## Who is kept out

Loopback binding limits reachability, not identity — a web page, including one
an agent opened in the dock's browser, can reach this port. A request carrying
an `Origin` header is refused outright, since the native HTTP client sends none and a
browser always does on a cross-origin POST; a request without a granted token
is refused next. Processes already running as the user are not defended
against, per `desktop/AGENTS.md`.

## Limits

HTTP allows one megabyte per request body and ten seconds to deliver a request.
Every HTTP reply is a single `application/json` body. Each tool handler has a
150-second deadline on either transport. The server sends no requests of its own.

## Cross-conversation messages

The backend registers one tool per action alongside the window's browser
tools: `session_list`, `session_read`, `session_send`, `session_start`,
`session_status`, and `session_cancel`. They form the `session` group; include
`session` in `X-SeekMoon-Tool-Groups` if a configured client filters groups.
These operate on OpenSeek conversations attached to this host, not Codex
threads or independent CLI processes.

`session_list` takes optional `offset` and `limit`. It returns a flat
`sessions` array containing only `id`, `title` (or `null`), and `workspace`,
plus `next_offset` (`null` at the end). Pass the returned offset to the next
`session_list` call. `limit` defaults to 20 and allows 1–50; a serialized size
budget may end a page earlier. Offsets refer to the
current inventory, so concurrent additions/removals can change pagination.
Listing failures use the tool error channel. There is no title/ID search
parameter; inspect the pages, and ask the user to choose or create a chat if
the intended one is absent. The sidebar keeps its existing grouped format.

`session_read` takes a `session` id and returns that conversation's saved
history.

`session_send` takes `target`, the exact `text`, and a caller-generated
`request_id`. The sender comes from the bearer grant. Identical retries of that request id
recover the original request; changing the target or text requires a new id
and another approval. The user reviews the destination and full message in the
sender's approval card. Approval may steer a running conversation or start a
turn in an idle one. It authorizes delivery of this message, not arbitrary
actions by its recipient.

The call waits 30 seconds for approval. After a timely approval it waits up to
30 more seconds for the target's durable user-message commit. A confirmed
commit returns `sent`; if delivery is still in progress, it returns `delivering`
and transfers the final result to background notification. An unanswered
approval returns `pending_approval` with an `id` and remains actionable. Both
waits are bounded below the ordinary MCP deadlines: 120 seconds for the agent
bridge and 150 seconds for the HTTP exchange and host handler. Cancelling or
timing out a waiter also transfers its final result to background notification;
it does not cancel the host-owned message delivery. `session_status` takes the
returned `id` and reads the current outcome; `session_cancel` takes it and
withdraws an unapproved request. Neither creates another delivery.
After a background decision, the host actively delivers the final result to
the sender's agent context, steering its current turn or starting a new one.
Rejections and delivery failures are reported too. A result-notification
failure stays visible in status and is reported to the frontend.

Each delivery is submitted once. A dropped steer, an unwritten command, or a
conversation that is compacting reports failure; the host does not resubmit
the message. Reusing the same `request_id` returns that recorded outcome.

### Starting a conversation

`session_start` takes a short `title`, the complete brief as `text`, and a
caller-generated `request_id`. It proposes a new OpenSeek chat in a new git
worktree of the caller's workspace, with the brief as its first prompt and the
system prompt, model, thinking level and approval mode the caller has when it
proposes. The host mints the new chat's id when the proposal is made, so the
result's `target` already names it; identical retries recover the same
proposal and the same id.

A proposal never waits: `session_start` returns `proposed` at once and the caller's
turn goes on. The caller's chat shows the proposal as a collapsed row above
the composer, which the user can start or dismiss at any time while the host
runs, however many turns later. The row goes away once the new chat exists. The proposal and the chat it starts share one token:
`msg-<token>` starts `desktop-<token>`. Starting it creates the worktree and
submits the first turn. The start succeeds once the new chat's first event is
saved, when the host also gives it the requested title; a run that ends before
then fails the start, and a failed start removes the worktree it created. A
host that closes while a start is in flight stops the new chat like any other
running chat and keeps its worktree.

Once the new chat has started, the host delivers a `<session_message_result>`
with `status="started"` and the new chat's `target` to the caller, steering
its current turn or starting a new one. From then on the caller follows the
chat like any other, with `session_read` and `session_send`. The caller is not told when the
user dismisses a proposal; `session_status` reports `proposed`, `starting`,
`started`, `dismissed`, `cancelled` or `failed`, and `session_cancel` withdraws a
proposal that is still open.

A caller that is not saved in a workspace, or whose workspace is not a git
repository, cannot start a chat.

Host message approvals survive tool cancellation, turn completion and frontend
reconnection. They are process-lifetime state: closing the host discards
outstanding requests. Engine-owned approvals retain their
existing turn-bound lifetime and have priority when both need attention.

### Try it in the development app

Configure the HTTP `seekmoon` entry above (replace an old stdio entry of the
same name), then start a new OpenSeek turn so its engine reloads the MCP
configuration. Use two saved OpenSeek chats on the same host. In the sender,
ask the agent to use the `seekmoon` `session_*` tools to list chats, find the
intended target, and send an exact test message. The source chat shows a `session.send`
approval with the destination and message.

- Approve within 30 seconds: the tool returns `sent` after the target records
  the input. If acknowledgement takes more than another 30 seconds, the tool
  returns `delivering`; the sender receives the final result asynchronously.
- Leave it unanswered for more than 30 seconds: the tool returns
  `pending_approval`. Approve the same card later; the target receives the
  message and the sender receives an active final-result notification.
- Deny the card: the target receives nothing and the sender receives
  `rejected`, synchronously or as a background result.

These tools are offered to the OpenSeek engine; Codex-backed chats are not
message targets for this implementation.

## Session artifacts

The backend adds two tools to hosts that provide this server:

- `artifacts_list({})` returns the current session's saved `{ "artifacts": [...] }`.
- `artifacts_attach({ "type": "pull_request", "url": "https://github.com/example/project/pull/42" })`
  appends one artifact and returns the saved list. Repeating an attachment is
  idempotent; existing entries remain. Agents have no detach, clear, or list
  replacement tool. Removal is available to authenticated frontend clients.

The stored and returned list has this shape:

```json
{
  "artifacts": [
    { "type": "pull_request", "url": "https://github.com/example/project/pull/42" },
    { "type": "branch", "url": "https://github.com/example/project/tree/feature/example" }
  ]
}
```

Each entry requires `type` (`pull_request` or `branch`) and `url`. The host
trims surrounding whitespace and trailing slashes and deduplicates by the
pair `(type, normalized URL)`, preserving insertion order. It checks basic
HTTPS URL syntax without querying the remote or changing the checkout.
Malformed arguments leave the list unchanged. The session comes from the
MCP grant, never from a tool argument. Unpublished local branches cannot be
attached by name.

Attaching requires an existing live session record; a stale grant cannot
recreate an archived or deleted session. Listing a session with no live
record or no sidecar returns an empty list, while read/parse failures remain
tool errors. Each attach reads and appends under the shared lock, so
concurrent attachments retain both additions without a read-then-write step.

The list lives beside the session transcript in `artifacts.json`, and moves
with that session when archived/restored/deleted. Artifacts are explicit
associations; automatic checkout facts are not written into this list.
The [Desktop session protocol](../../../docs/remote-protocol.md#session-artifacts)
documents frontend list/remove commands and the `session.artifacts_changed`
notification emitted after a save. Removal targets an exact type and URL
against the latest list, preserving unrelated concurrent additions.

These tools belong to the `artifacts` group. If the configuration filters
groups with `X-SeekMoon-Tool-Groups`, include `artifacts` (for example
`browser,artifacts`).
