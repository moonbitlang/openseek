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

Tool results reach the model as text plus images. Text content is passed
through; PNG, JPEG, GIF, and WebP image content (at most 20 MiB, MIME type
matching the bytes) is attached as image input, like `image` output. On a
model route without image input, a result carrying images becomes a tool
error, as for any image tool result. Other image formats, audio, and resource
links are replaced by short text placeholders.

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

## OAuth for HTTP servers

A skill's `mcp.json` can declare a public OAuth client instead of a static
Authorization header or `headersHelper`:

```json
{
  "mcpServers": {
    "github": {
      "url": "https://api.githubcopilot.com/mcp/",
      "oauth": {
        "grantType": "device_code",
        "clientId": "Ov23liDY0j2riv3dZtVY",
        "deviceAuthorizationEndpoint": "https://github.com/login/device/code",
        "tokenEndpoint": "https://github.com/login/oauth/access_token",
        "scopes": "repo read:org"
      }
    }
  }
}
```

This is the Device Authorization Grant. The bundled GitHub skill uses the
OpenSeek OAuth App. Desktop displays the provider's URL and user code, and the
host polls at the provider's interval.

For a server that supports public client registration and S256 PKCE, use the
Authorization Code Grant in the skill's `mcp.json`:

```json
{
  "mcpServers": {
    "example": {
      "url": "https://mcp.example.com/mcp",
      "oauth": {
        "grantType": "authorization_code",
        "issuer": "https://mcp.example.com"
      }
    }
  }
}
```

Copy the skill directory into `~/.openseek/skills/` (or the library set by
`OPENSEEK_GLOBAL_SKILLS_DIR`), then connect the server in Desktop Settings → MCP.

For `authorization_code`, the MCP URL and discovered OAuth endpoints must
belong to the configured HTTPS issuer. OpenSeek reads protected resource and
issuer metadata, registers and reuses a public client, and verifies the
provider's redirect on a loopback listener with a temporary port. The browser
must run on the same computer as the host. The host exchanges the code
directly with the provider.

Desktop Settings → MCP lists MCP configurations in bundled and globally
installed skills. Globally installed skills override bundled skills of the
same name. Connect opens the provider's page. Workspace-only skills and
standalone MCP configurations are outside this settings list. An explicit MCP
config overrides a same-named skill server.

Credentials and public client registrations are stored under
`~/.openseek/oauth` (`OPENSEEK_OAUTH_DIR` overrides this). Files are atomically
replaced with mode 0600 on POSIX and the directory is created with mode 0700.
The settings UI receives status only. The engine refreshes browser grants
before expiry and serializes refreshes across processes so each rotated token
is saved before the next refresh. Device grants require reconnect after expiry.
The next tool search or call reloads changed credentials and resets the
connection. Disconnect deletes the local credential. Provider-side revocation
is separate.

OAuth configuration cannot be combined with an Authorization header or
`headersHelper`. Environment placeholders expand as in other MCP fields.
