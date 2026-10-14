# Host tools

How the agents a desktop host runs use capabilities only the host has — the
dock's browser tabs, to begin with. Two halves live here: the server the host
runs, and the `seekmoon` command through which an engine reaches it as a
stdio MCP server.

The MCP client engines use for the user's own servers is the root module's
`mcp/`; it is what connects to `seekmoon`, and shares no code with this.

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
- `stdio.mbt` — `seekmoon mcp`, as a function from a command line, an
  environment, and a pair of streams to an exit status.
- `client.mbt` — how the command sends one message to the server.
- `cmd/seekmoon` — the executable around it.

## The command

`seekmoon mcp` serves the host's tools to an MCP client over stdin and
stdout. A user lists it in an MCP configuration like any other stdio server:

```json
{ "mcpServers": { "seekmoon": { "command": "seekmoon", "args": ["mcp"] } } }
```

The engine that reads that file starts the process, which inherits the
engine's environment and with it a grant (below). The tools reach the model
as `mcp__seekmoon__<tool>`.

The host's server already speaks MCP, so the command is a relay: each line
from the client is POSTed to the host as it is, and the host's reply is
written back as one line. Messages are relayed concurrently, so a slow tool
call does not hold up a `ping` behind it. When the host cannot be reached a
request is answered with an error and the command stays up; when its input
ends it answers what it has already read and exits.

`seekmoon mcp browser` offers only the groups it names, a tool's group being
its name up to the first underscore. Every tool a server lists rides every
request its client makes, and a client caps how many it will take, so a
configuration can ask for less than everything.

## Grants

A grant is two environment variables: `OPENSEEK_DESKTOP_TOOLS_URL`, where the
server is, and `OPENSEEK_DESKTOP_TOOLS_TOKEN`, a bearer token minted for one
conversation on first use and kept for the launch. `Server::grant(session)`
returns them and the engine actor sets them on every engine it starts for that
conversation — a `serve` engine and a scheduled run alike.

The token is how a handler knows who is calling: `ToolCall.session` comes from
the token, never from arguments the model wrote. Everything an engine runs
inherits its environment, so a sub-run or a background job acts for the
conversation that started it. Nothing is written to disk.

A host that offers no tools removes both variables from the engines it starts,
so a grant it inherited — a host launched from another host's agent — is not
passed on.

## Who is kept out

Loopback binding limits reachability, not identity — a web page, including one
an agent opened in the dock's browser, can reach this port. A request carrying
an `Origin` header is refused outright, since `seekmoon` never sends one and a
browser always does on a cross-origin POST; a request without a granted token
is refused next. Processes already running as the user are not defended
against, per `desktop/AGENTS.md`.

## Limits

One megabyte per request body, ten seconds to deliver a request, and 150
seconds per tool handler. Every reply is a single `application/json` body:
there is no SSE stream and no server-initiated request.
