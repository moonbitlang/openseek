# Host tools

How the agents a desktop host runs use capabilities only the host has — the
dock's browser tabs, to begin with. Two halves live here: the server the host
runs, and the `seekmoon` command an agent runs to call it.

The package is named for its wire format. The server speaks MCP's tool
methods (`tools/list`, `tools/call`) as JSON-RPC over HTTP, so an MCP client
can talk to it; the MCP client engines use for the user's own servers is the
root module's `mcp/` and shares no code with this.

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
- `cli.mbt` — `seekmoon tools`, as a function from a command line and an
  environment to what it prints and its exit status.
- `stdio.mbt` — `seekmoon mcp`, the same tools as a stdio MCP server.
- `cmd/seekmoon` — the executable around the two.

## The command

`seekmoon` knows no tool by name. It asks the server what it offers and builds
its command line from the answer:

- Tools live under `seekmoon tools`, which leaves the top level free for
  whatever else the command grows.
- A tool named `browser_get_text` is run as `seekmoon tools browser get-text`.
  The text before the first underscore groups related tools; the rest is the
  verb.
- Each top-level property of the tool's input schema is an option of the same
  name, with underscores written as hyphens. A string is passed as written, a
  boolean is a flag, and anything else is given as JSON (`--tab 3`,
  `--viewport '{"width":800}'`).
- The tool's text goes to stdout and the exit status is 0. A tool that fails
  puts its message on stderr and exits 1, as does a host that cannot be
  reached. A command line no tool accepts exits 2 without calling anything.

So a host package that contributes a tool gets its command, its options, and
its `--help` with no code here.

An agent runs commands from sandboxed scripts that may start only programs on
the engine's allowlist, so `seekmoon` has to be on it before an agent can use
it this way.

## As an MCP server

`seekmoon mcp` serves the same tools to a client that wants them as MCP tools.
A user lists it in an MCP configuration like any other stdio server:

```json
{ "mcpServers": { "seekmoon": { "command": "seekmoon", "args": ["mcp"] } } }
```

The engine that reads that file starts the process, which inherits the
engine's environment and so holds the same grant `seekmoon tools` uses. It is
a relay: each line from the client is POSTed to the host as it is, and the
host's reply is written back as one line. When the host cannot be reached a
request is answered with an error and the server stays up.

`seekmoon mcp browser` offers only the groups it names. Every tool a server
lists rides every request its client makes, and a client caps how many it will
take, so a configuration can ask for less than everything.

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
