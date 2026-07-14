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
/// A malformed MCP configuration.
pub(all) suberror ConfigError {
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
  let out = []
  for name, entry in servers {
    out.push(decode_server(name, entry))
  }
  out
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
  let args = []
  if entry is { "args": args_value, .. } {
    guard args_value is Array(items) else {
      raise Invalid("server `\{name}`: `args` must be an array of strings")
    }
    for item in items {
      guard item is String(arg) else {
        raise Invalid("server `\{name}`: every `args` entry must be a string")
      }
      args.push(arg)
    }
  }
  let env : Map[String, String] = Map([])
  if entry is { "env": env_value, .. } {
    guard env_value is Object(vars) else {
      raise Invalid("server `\{name}`: `env` must be an object of strings")
    }
    for key, value in vars {
      guard value is String(text) else {
        raise Invalid("server `\{name}`: every `env` value must be a string")
      }
      env[key] = text
    }
  }
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
  let headers : Map[String, String] = Map([])
  if entry is { "headers": headers_value, .. } {
    guard headers_value is Object(vars) else {
      raise Invalid("server `\{name}`: `headers` must be an object of strings")
    }
    for key, value in vars {
      guard value is String(text) else {
        raise Invalid(
          "server `\{name}`: every `headers` value must be a string",
        )
      }
      headers[key] = text
    }
  }
  Http(name~, url~, headers~)
}
