///|
/// Transport-independent MCP tools and JSON-RPC dispatch. Handlers keep the
/// browser and session objects supplied by the host that constructs them.
struct Dispatcher {
  version : String
  tools : Map[String, Tool]
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
  let names : Set[String] = Set([])
  for tool in tools {
    if self.tools.contains(tool.name) || names.contains(tool.name) {
      raise ServerError("duplicate host tool: \{tool.name}")
    }
    names.add(tool.name)
  }
  for tool in tools {
    self.tools[tool.name] = tool
  }
}

///|
/// Reported as `serverInfo.name`.
const ServerName = "seekmoon"
