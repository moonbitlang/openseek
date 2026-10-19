# MCP tool connections

`stdio.connect` and `streamhttp.connect` prefer the stateless MCP `2026-07-28`
revision. They send `server/discover`, select the supported revision, and attach
protocol version, client identity, and an empty client-capabilities object to
every subsequent request's `params._meta`. Modern connections do not send
`initialize` or `notifications/initialized` and do not acquire MCP sessions.

The terminology follows the specification: **modern** means `2026-07-28` and
later, **legacy** means revisions using the initialization handshake. Only
`2026-07-28` is implemented on the modern path; unknown revisions are rejected.

## Compatibility

For stdio, a non-modern discovery error or a probe timeout selects the existing
legacy handshake. The probe uses at most one second and at most one quarter of
the connection deadline. For HTTP, a legacy discovery error or an HTTP
400/404/405 without a recognized modern error selects the legacy path.
Authentication failures, network failures, malformed discovery successes, and
recognized modern protocol errors do not trigger a downgrade.

Legacy peers continue to use `2025-11-25`, `2025-06-18`, `2025-03-26`, or
`2024-11-05`, including the existing HTTP session header and teardown behavior.
The deprecated HTTP+SSE transport with a separate GET endpoint is not implemented.

## HTTP metadata and cancellation

Modern HTTP requests mirror version, method, and tool name into their required
headers. A direct first tool call automatically lists tools (including all
pages) if the caller has not done so, to obtain the parameter header schemas.
`x-mcp-header` annotations are validated when listing tools; invalid
definitions are excluded. Annotated primitive arguments are mirrored into
`Mcp-Param-*` headers, including nested properties. Unicode, control characters,
surrounding whitespace, and literal Base64 sentinels use the prescribed encoding.
Configured headers cannot override these protocol-owned fields.

Cancelling an outstanding modern stdio call sends `notifications/cancelled`.
Cancellation of an already dispatched request is retained separately from the
bounded outbound queue and sent when the writer can resume. A cancelled request
that has not reached the transport is discarded without executing it.
Cancelling an HTTP call closes only that request's exchange; other calls remain
usable. Independent server-to-client JSON-RPC requests are ignored on modern
transports, which never answer them with JSON-RPC responses.

## Supported surface

The client exposes discovery, paginated tool listing, and tool calls. It does
not advertise sampling, elicitation, roots, or subscription capabilities.
`input_required` and unknown result types surface as protocol errors instead
of becoming empty successful tool output. Automatic MRTR continuation is not
implemented. Missing `resultType` is accepted as `complete`, as required for
backward compatibility.

The desktop host serves modern discovery and tools alongside legacy clients on
the same endpoint. It validates metadata and mirrored headers independently on
each request, accepts direct tool calls without prior discovery, and returns
`resultType: "complete"` and server identity on modern results. The existing
bearer grant determines the OpenSeek conversation; self-reported client metadata
does not grant authority.

References: [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning),
[stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio),
[Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http),
[MRTR](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr).
