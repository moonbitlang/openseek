// What a running engine holds of the MCP servers it was configured with: the
// payload of the `mcp_status` event, which the engine sends on its own when
// it has connected them and whenever that state changes. It is the engine's
// own state — the connections a conversation actually has, not what
// connecting afresh would yield.

///|
/// One tool a connected MCP server registered, under its namespaced name
/// (`mcp__<server>__<tool>`).
pub(all) struct McpTool {
  name : String
  description : String
} derive(Eq, Debug)

///|
pub extend McpTool with Eq::{equal, not_equal}

///|
pub extend McpTool with Debug::{to_repr}

///|
pub impl ToJson for McpTool with fn to_json(self) {
  { "name": Json(self.name), "description": Json(self.description) }
}

///|
pub impl FromJson for McpTool with fn from_json(json, path) {
  guard json is { "name": String(name), "description": String(description), .. } else {
    raise JsonDecodeError((path, "invalid McpTool"))
  }
  { name, description, }
}

///|
pub extend McpTool with ToJson::{to_json}

///|
pub extend McpTool with FromJson::{from_json}

///|
/// How a configured server is reached: a subprocess speaking over stdio, or a
/// Streamable HTTP endpoint.
pub(all) enum McpTransport {
  Stdio
  Http
} derive(Eq, Debug)

///|
pub extend McpTransport with Eq::{equal, not_equal}

///|
pub extend McpTransport with Debug::{to_repr}

///|
/// What the engine holds of one configured server.
pub(all) enum McpServerState {
  /// Connected, with the tools it registered (never empty).
  Connected(Array[McpTool])
  /// It connected and registered these tools, and the connection has closed
  /// since — the server exited or the transport broke. The tools are still in
  /// the model's registry and calls to them fail.
  Lost(Array[McpTool])
  /// Connected, and it offered no tools, so the engine released it.
  NoTools
  /// It could not be started, reached, or asked for its tools.
  Failed(String)
  /// Never tried: earlier servers had already used up the tool budget.
  Skipped
} derive(Eq, Debug)

///|
pub extend McpServerState with Eq::{equal, not_equal}

///|
pub extend McpServerState with Debug::{to_repr}

///|
/// One server of the configuration. `target` is its command (stdio) or its
/// URL without credentials (http); arguments, environment, and headers are
/// never reported because they are where tokens live.
pub(all) struct McpServerStatus {
  name : String
  transport : McpTransport
  target : String
  state : McpServerState
} derive(Eq, Debug)

///|
pub extend McpServerStatus with Eq::{equal, not_equal}

///|
pub extend McpServerStatus with Debug::{to_repr}

///|
pub impl ToJson for McpServerStatus with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json(self.name),
    "transport": match self.transport {
      Stdio => "stdio"
      Http => "http"
    },
    "target": Json(self.target),
  }
  match self.state {
    Connected(tools) => {
      fields["state"] = "connected"
      fields["tools"] = Json(tools)
    }
    Lost(tools) => {
      fields["state"] = "lost"
      fields["tools"] = Json(tools)
    }
    NoTools => fields["state"] = "no_tools"
    Failed(error) => {
      fields["state"] = "failed"
      fields["error"] = Json(error)
    }
    Skipped => fields["state"] = "skipped"
  }
  Json::object(fields)
}

///|
pub impl FromJson for McpServerStatus with fn from_json(json, path) {
  guard json
    is {
      "name": String(name),
      "transport": String(transport),
      "target": String(target),
      "state": String(state),
      ..
    } else {
    raise JsonDecodeError((path, "invalid McpServerStatus"))
  }
  let transport : McpTransport = match transport {
    "stdio" => Stdio
    "http" => Http
    _ => raise JsonDecodeError((path.add_key("transport"), "invalid transport"))
  }
  // A server holding tools always lists them: an empty list would be a
  // connected server with nothing registered, which is `no_tools`.
  fn held_tools() -> Array[McpTool] raise @json.JsonDecodeError {
    guard json is { "tools": listed, .. } else {
      raise JsonDecodeError((path, "missing tools"))
    }
    let tools : Array[McpTool] = @json.from_json(
      listed,
      path=path.add_key("tools"),
    )
    guard !tools.is_empty() else {
      raise JsonDecodeError((path.add_key("tools"), "expected at least one"))
    }
    tools
  }

  let state : McpServerState = match state {
    "connected" => Connected(held_tools())
    "lost" => Lost(held_tools())
    "no_tools" => NoTools
    "failed" => {
      guard json is { "error": String(error), .. } else {
        raise JsonDecodeError((path, "missing error"))
      }
      Failed(error)
    }
    "skipped" => Skipped
    _ => raise JsonDecodeError((path.add_key("state"), "invalid state"))
  }
  { name, transport, target, state, }
}

///|
pub extend McpServerStatus with ToJson::{to_json}

///|
pub extend McpServerStatus with FromJson::{from_json}

///|
/// The engine's MCP configuration and what came of it.
pub(all) enum McpStatus {
  /// The engine was started without an MCP configuration.
  NotConfigured
  /// It was pointed at a file it could not use — unreadable, not JSON, or
  /// not the `mcpServers` shape — so it has no servers.
  ConfigFailed(path~ : String, error~ : String)
  /// The configuration loaded; these are its servers, in file order.
  Configured(path~ : String, servers~ : Array[McpServerStatus])
} derive(Eq, Debug)

///|
pub extend McpStatus with Eq::{equal, not_equal}

///|
pub extend McpStatus with Debug::{to_repr}

///|
pub impl ToJson for McpStatus with fn to_json(self) {
  match self {
    NotConfigured => { "config": "none" }
    ConfigFailed(path~, error~) =>
      { "config": "failed", "path": Json(path), "error": Json(error) }
    Configured(path~, servers~) =>
      { "config": "loaded", "path": Json(path), "servers": Json(servers) }
  }
}

///|
pub impl FromJson for McpStatus with fn from_json(json, path) {
  match json {
    { "config": "none", .. } => NotConfigured
    {
      "config": "failed",
      "path": String(config_path),
      "error": String(error),
      ..
    } => ConfigFailed(path=config_path, error~)
    { "config": "loaded", "path": String(config_path), "servers": listed, .. } =>
      Configured(
        path=config_path,
        servers=@json.from_json(listed, path=path.add_key("servers")),
      )
    _ => raise JsonDecodeError((path, "invalid McpStatus"))
  }
}

///|
pub extend McpStatus with ToJson::{to_json}

///|
pub extend McpStatus with FromJson::{from_json}
