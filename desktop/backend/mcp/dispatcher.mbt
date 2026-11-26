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

///|
/// A failure of the server itself, as opposed to one of its tools.
pub suberror ServerError {
  ServerError(String)
}

///|
pub impl Show for ServerError with fn output(self, logger) {
  let ServerError(message) = self
  logger.write_string(message)
}

///|
pub extend ServerError with Show::{output, to_string}
