// Decode openseek's MCP server configuration — the de-facto standard
// `{ "mcpServers": { "<name>": { … } } }` shape, so an existing
// Claude/Cursor-style `mcp.json` can be pointed at directly. A server entry is
// either a stdio server (`"command"` + optional `"args"`/`"env"`) or a
// Streamable HTTP server (`"url"` + optional `"headers"`). File reading and
// JSON parsing are the caller's; this layer is pure and decodes a parsed `Json`.

///|
/// A configured MCP server: launched as a subprocess (stdio) or reached at a
/// Streamable HTTP endpoint.
pub(all) enum McpServer {
  Stdio(
    name~ : String,
    command~ : String,
    args~ : Array[String],
    env~ : Map[String, String]
  )
  Http(name~ : String, url~ : String, headers~ : Map[String, String])
} derive(Eq, Debug)

///|
/// The configured server's name (the key under `mcpServers`).
pub fn McpServer::name(self : McpServer) -> String {
  match self {
    Stdio(name~, ..) | Http(name~, ..) => name
  }
}

///|
/// What identifies the server to a person without echoing a secret: its
/// command (stdio), or its URL without userinfo and query (http). Arguments,
/// environment, and headers are left out because that is where tokens live.
pub fn McpServer::target(self : McpServer) -> String {
  match self {
    Stdio(command~, ..) => command
    Http(url~, ..) => redact_url(url)
  }
}

///|
/// Strip userinfo (`user:pass@`) and the query/fragment from `url`, keeping
/// scheme, host, and path — enough to identify the endpoint without echoing
/// embedded credentials.
fn redact_url(url : String) -> String {
  // Cut at the first `?` or `#`, then locate the authority after the FIRST
  // `://` anywhere — matching the decoder's leniency and staying fail-closed
  // for malformed values like `/https://user:secret@host` — and drop a
  // `userinfo@` that precedes any `/` in what follows. The userinfo arm is
  // start-anchored on purpose: an unanchored lexmatch arm SEARCHES, and would
  // redact an `@` sitting in the path.
  let kept = if url =~ (re"[?#]", before~, after=_) { before } else { url }
  let (prefix, rest) = if kept =~ (re"://", before~, after~) {
    ("\{before}://", after)
  } else {
    ("", kept)
  }
  lexmatch rest {
    re"^[^/@]*@" + (re"(.|\n)*$" as tail) => "\{prefix}\{tail}"
    _ => "\{prefix}\{rest}"
  }
}

///|
/// A malformed MCP configuration.
pub suberror ConfigError {
  Invalid(String)
}

///|
impl Show for ConfigError with fn output(self, logger) {
  match self {
    Invalid(message) => logger.write_string("mcp config error: \{message}")
  }
}

///|
/// Decode the parsed configuration into the list of configured servers. Raises
/// `ConfigError` when the shape is wrong. An empty or absent `mcpServers` is not
/// an error at this layer — the caller decides whether zero servers is expected.
pub fn decode(json : Json) -> Array[McpServer] raise {
  guard json is { "mcpServers": Object(servers), .. } else {
    raise Invalid("configuration is missing an `mcpServers` object")
  }
  [
    for name, entry in servers => decode_server(name, entry)
  ]
}

///|
/// Decode one server entry keyed by `name`: `"url"` marks a Streamable HTTP
/// server, `"command"` a stdio one; exactly one of the two must be present.
fn decode_server(name : String, entry : Json) -> McpServer raise {
  if entry is { "url": _, .. } {
    return decode_http_server(name, entry)
  }
  guard entry is { "command": String(command), .. } else {
    raise Invalid(
      "server `\{name}` needs a string `command` (stdio) or `url` (http)",
    )
  }
  // A present-but-mistyped optional field is a config mistake, not an omission:
  // silently treating `"args": "--flag"` as no args would launch the server
  // wrong. Absent keys stay optional.
  let args = if entry is { "args": args_value, .. } {
    guard args_value is Array(items) else {
      raise Invalid("server `\{name}`: `args` must be an array of strings")
    }
    [
      for item in items => {
        guard item is String(arg) else {
          raise Invalid("server `\{name}`: every `args` entry must be a string")
        }
        arg
      }
    ]
  } else {
    []
  }
  let env = decode_string_map(name, entry, "env")
  Stdio(name~, command~, args~, env~)
}

///|
/// Decode a Streamable HTTP server entry (its `url` key is already known to be
/// present).
fn decode_http_server(name : String, entry : Json) -> McpServer raise {
  guard entry is { "url": String(url), .. } else {
    raise Invalid("server `\{name}`: `url` must be a string")
  }
  if entry is { "command": _, .. } {
    raise Invalid(
      "server `\{name}`: give `command` (stdio) or `url` (http), not both",
    )
  }
  let headers = decode_string_map(name, entry, "headers")
  Http(name~, url~, headers~)
}

///|
/// An optional object-of-strings field: absent yields empty, present-but-
/// mistyped is an error.
fn decode_string_map(
  name : String,
  entry : Json,
  field : String,
) -> Map[String, String] raise {
  let out : Map[String, String] = Map([])
  guard entry is Object(fields) && fields.get(field) is Some(value) else {
    return out
  }
  guard value is Object(vars) else {
    raise Invalid("server `\{name}`: `\{field}` must be an object of strings")
  }
  for key, item in vars {
    guard item is String(text) else {
      raise Invalid("server `\{name}`: every `\{field}` value must be a string")
    }
    out[key] = text
  }
  out
}

///|
#doc(hidden)
#deprecated
pub extend McpServer with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend McpServer with Eq::{equal, not_equal}
