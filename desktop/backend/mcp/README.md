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

For a host configured with tools, add an HTTP entry to `~/.openseek/mcp.json`:

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
reach the model as `mcp__seekmoon__<tool>`; without an entry no tools are added.
The old `seekmoon mcp` stdio relay and executable have been removed.

To offer a subset, add `"X-SeekMoon-Tool-Groups": "browser"` to the headers.
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
conversation that started it. Nothing is written to disk.

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
