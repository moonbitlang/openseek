// The contract between this server and the host packages that contribute
// tools to it. A tool is a name, the description and schema the model reads,
// and a handler; the server owns everything about the wire.

///|
/// One `tools/call`, as its handler sees it.
pub(all) struct ToolCall {
  // The conversation the call is made for, recovered from the bearer token
  // it was granted — never from anything the model wrote.
  session : String
  // The call's `arguments`, as sent. Handlers decode what they declared in
  // their schema and raise `ToolError` for anything else.
  arguments : Json
}

///|
/// One tool this host offers to the agents it runs.
pub(all) struct Tool {
  name : String
  description : String
  // The JSON Schema of `arguments`, sent as `inputSchema`.
  input_schema : Json
  // Returns the text the model reads. Raising makes the call a tool-level
  // failure (`isError`), which the model also reads and can react to.
  call : async (ToolCall) -> String
}

///|
/// A failure whose message is written for the model: what went wrong and,
/// where there is one, what to do instead.
pub(all) suberror ToolError {
  ToolError(String)
}

///|
pub impl Show for ToolError with fn output(self, logger) {
  let ToolError(message) = self
  logger.write_string(message)
}

///|
pub extend ToolError with Show::{to_string, output}
