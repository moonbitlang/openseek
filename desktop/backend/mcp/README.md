# Host MCP server

The host side of MCP: a loopback Streamable HTTP server through which the
engines this host spawns call host-owned tools. The MCP *client* those engines
use is the root module's `mcp/`; this package is the other end and shares no
code with it.

It depends on async HTTP and core codecs, not on Proton, the engine, or any
package that contributes tools. Dependencies point inward: a package that owns
a capability builds `Tool` values over it, and the host binds one `Server`
with them and hands it to `@api.ApiState`. From there the engine actor asks
the server for each engine's config, and `ApiState::start_services` serves it
alongside the backend's other app-lifetime owners.

## Shape

- `tool.mbt` — the contract a contributing package implements: `Tool` (name,
  description, input schema, handler) and `ToolCall` (the calling conversation
  and the arguments). A handler returns the text the model reads; raising makes
  the call a tool-level failure the model also reads.
- `protocol.mbt` — JSON-RPC dispatch for `initialize`, `ping`, `tools/list`,
  and `tools/call`. Nothing else is offered.
- `server.mbt` — the listener, the bearer-token grants, and one task per
  request.
- `config.mbt` — the engine config file that carries a grant to an engine.

## Grants

An engine reads its MCP servers from one JSON file named by `--mcp-config`,
once, when it starts. `Server::engine_config(session~)` writes that file: the
user's own config when they have one (`OPENSEEK_MCP_CONFIG`), with this server
added under the name `seekmoon` and the conversation's bearer token in its
`Authorization` header. Tools therefore reach the model as
`mcp__seekmoon__<tool>`.

A token is minted per conversation on first use and lasts for the launch. It
is how a handler knows who is calling: `ToolCall.session` comes from the token,
never from arguments the model wrote.

## Who is kept out

Loopback binding limits reachability, not identity — a web page, including one
an agent opened in the dock's browser, can reach this port. A request carrying
an `Origin` header is refused outright, since an engine never sends one and a
browser always does on a cross-origin POST; a request without a granted token
is refused next. Processes already running as the user are not defended
against, per `desktop/AGENTS.md`.

## Limits

One megabyte per request body, ten seconds to deliver a request, and 150
seconds per tool handler — past the engine's own per-call deadline, so a
handler cannot long outlive the caller that stopped waiting for it. Every
reply is a single `application/json` body: there is no SSE stream and no
server-initiated request.
