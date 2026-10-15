# Host tools

How agents connect to capabilities contributed by a desktop host. The host
can run an HTTP MCP server; the engine connects directly using the root
module's `mcp/streamhttp` client. This package supplies the server infrastructure;
the host chooses which tools to register.

It depends on async HTTP and core codecs, not on Proton, the engine, or any
package that contributes tools. Dependencies point inward: a package that owns
a capability builds `Tool` values over it, and the host constructs one
`Server` with them and hands it to `@api.ApiState`. From there the engine
actor grants every engine it starts access to the server, and
`ApiState::start_services` serves it alongside the backend's other
app-lifetime owners.

## Shape

- `tool.mbt` — the contract a contributing package implements: `Tool` (name,
  description, input schema, handler) and `ToolCall` (the calling conversation
  and the arguments). A handler returns the text the agent reads; raising makes
  the call a tool-level failure the agent also reads.
- `protocol.mbt` — JSON-RPC dispatch for `initialize`, `ping`, `tools/list`,
  and `tools/call`. Nothing else is offered.
- `server.mbt` — the listener, the grants, and one task per request.

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

One megabyte per request body, ten seconds to deliver a request, and 150
seconds per tool handler. Every reply is a single `application/json` body:
there is no SSE stream and no server-initiated request.

## Cross-conversation messages

The backend registers `session` alongside the window's browser tools. Include
`session` in `X-SeekMoon-Tool-Groups` if a configured client filters groups.
Its actions are `list`, `read`, `send`, `status`, and `cancel`. These operate on
OpenSeek conversations attached to this host, not Codex threads or independent
CLI processes.

`list` returns a flat `sessions` array containing only `id`, `title` (or
`null`), and `workspace`, plus `next_offset` (`null` at the end). Pass the
returned offset to the next `list` call. `limit` defaults to 20 and allows
1–50; a serialized size budget may end a page earlier. Offsets refer to the
current inventory, so concurrent additions/removals can change pagination.
Listing failures use the tool error channel. There is no title/ID search
parameter; inspect the pages, and ask the user to choose or create a chat if
the intended one is absent. The sidebar keeps its existing grouped format.

`send` takes `target`, the exact `text`, and a caller-generated `request_id`.
The sender comes from the bearer grant. Identical retries of that request id
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
it does not cancel the host-owned message delivery. `status` reads the current
outcome; `cancel` withdraws an unapproved request. Neither action creates another
delivery.
After a background decision, the host actively delivers the final result to
the sender's agent context, steering its current turn or starting a new one.
Rejections and delivery failures are reported too. A result-notification
failure stays visible in status and is reported to the frontend.

Each delivery is submitted once. A dropped steer, an unwritten command, or a
conversation that is compacting reports failure; the host does not resubmit
the message. Reusing the same `request_id` returns that recorded outcome.

Host message approvals survive tool cancellation, turn completion and frontend
reconnection. They are process-lifetime state: closing the host discards
outstanding requests. Engine-owned approvals retain their
existing turn-bound lifetime and have priority when both need attention.

### Try it in the development app

Configure the HTTP `seekmoon` entry above (replace an old stdio entry of the
same name), then start a new OpenSeek turn so its engine reloads the MCP
configuration. Use two saved OpenSeek chats on the same host. In the sender,
ask the agent to use `mcp__seekmoon__session` to list chats, find the intended
target, and send an exact test message. The source chat shows a `session.send`
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
