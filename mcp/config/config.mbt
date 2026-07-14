// Decode openseek's MCP server configuration — the de-facto standard
// `{ "mcpServers": { "<name>": { "command", "args"?, "env"? } } }` shape, so an
// existing Claude/Cursor-style `mcp.json` can be pointed at directly. File
// reading and JSON parsing are the caller's; this layer is pure and decodes a
// parsed `Json`.

///|
/// A configured MCP server. Only stdio servers exist today (launched as a
/// subprocess); an HTTP variant is added when that transport lands.
pub(all) enum McpServer {
  Stdio(
    name~ : String,
    command~ : String,
    args~ : Array[String],
    env~ : Map[String, String]
  )
} derive(Eq, Debug)

///|
/// The configured server's name (the key under `mcpServers`).
pub fn McpServer::name(self : McpServer) -> String {
  match self {
    Stdio(name~, ..) => name
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
/// Decode one server entry keyed by `name`.
fn decode_server(name : String, entry : Json) -> McpServer raise {
  guard entry is { "command": String(command), .. } else {
    raise Invalid("server `\{name}` is missing a string `command`")
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
