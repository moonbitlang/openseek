///|
/// Transport-independent MCP tools and JSON-RPC dispatch. Handlers keep the
/// browser and session objects supplied by the host that constructs them.
pub struct Dispatcher {
  priv version : String
  priv tools : Map[String, Tool]
}

///|
/// Construct a dispatcher without opening any transport or process streams.
pub fn Dispatcher::Dispatcher(
  tools : Array[Tool],
  version~ : String,
) -> Dispatcher {
  { version, tools: Map::from_array(tools.map(tool => (tool.name, tool))), }
}

///|
/// Register a batch atomically before serving requests.
pub fn Dispatcher::add_tools(
  self : Dispatcher,
  tools : Array[Tool],
) -> Unit raise ServerError {
  let names : Map[String, Unit] = Map([])
  for tool in tools {
    if self.tools.contains(tool.name) || names.contains(tool.name) {
      raise ServerError("duplicate host tool: \{tool.name}")
    }
    names[tool.name] = ()
  }
  for tool in tools {
    self.tools[tool.name] = tool
  }
}

///|
/// Reported as `serverInfo.name`.
const ServerName = "seekmoon"
