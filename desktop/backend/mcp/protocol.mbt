// The MCP methods this server answers, as JSON-RPC messages in and out. The
// HTTP layer in `server.mbt` hands every authenticated POST body here and
// writes back whatever this returns.
//
// Scope: the tool surface only — `initialize`, `ping`, `tools/list`, and
// `tools/call`. Resources, prompts, and server-initiated requests are not
// offered, which the `initialize` capabilities say.

///|
/// The newest protocol revision this server speaks, answered when a client
/// asks for one it does not.
const LatestProtocolVersion = "2025-11-25"

///|
/// Whether this server can speak `version`. The methods it answers are
/// unchanged across these revisions.
fn supported_version(version : String) -> Bool {
  version == LatestProtocolVersion ||
  version == "2025-06-18" ||
  version == "2025-03-26" ||
  version == "2024-11-05"
}

///|
/// The deadline for one tool handler. An engine stops waiting for a call
/// after its own, shorter deadline, so a handler still running here has no
/// reader left; this bounds how long it can outlive that.
const CallTimeoutMs : Int = 150000

///|
const InvalidRequest : Int = -32600

///|
const MethodNotFound : Int = -32601

///|
const InvalidParams : Int = -32602

///|
fn reply(id : Json, result : Json) -> Json {
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
fn failure(id : Json, code : Int, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id,
    "error": { "code": code.to_json(), "message": message.to_json() },
  }
}

///|
/// Answer one inbound message from `session`'s engine. `None` when the
/// message expects no reply: a notification, or a response to a request —
/// which this server never sends, so there is nothing to match it to.
async fn Server::dispatch(
  self : Server,
  session : String,
  message : Json,
) -> Json? {
  guard message is Object(fields) else {
    // JSON-RPC answers an unidentifiable request under a null id.
    return Some(failure(Json::null(), InvalidRequest, "Invalid Request"))
  }
  guard fields.get("method") is Some(String(method_)) else {
    if fields.contains("result") || fields.contains("error") {
      return None
    }
    return Some(
      failure(
        fields.get("id").unwrap_or(Json::null()),
        InvalidRequest,
        "Invalid Request",
      ),
    )
  }
  guard fields.get("id") is Some(id) else { return None }
  let params = fields.get("params").unwrap_or(Json::empty_object())
  let answer = match method_ {
    "initialize" => reply(id, self.initialize_result(params))
    "ping" => reply(id, Json::empty_object())
    "tools/list" => reply(id, self.tool_list())
    "tools/call" => self.call_tool(session, id, params)
    _ => failure(id, MethodNotFound, "Method not found: \{method_}")
  }
  Some(answer)
}

///|
fn Server::initialize_result(self : Server, params : Json) -> Json {
  let version = match params {
    { "protocolVersion": String(requested), .. } if supported_version(requested) =>
      requested
    _ => LatestProtocolVersion
  }
  {
    "protocolVersion": version.to_json(),
    "capabilities": { "tools": Json::empty_object() },
    "serverInfo": {
      "name": ServerName.to_json(),
      "version": self.version.to_json(),
    },
  }
}

///|
fn Server::tool_list(self : Server) -> Json {
  let tools : Array[Json] = [
    for _, tool in self.tools => {
      {
        "name": tool.name.to_json(),
        "description": tool.description.to_json(),
        "inputSchema": tool.input_schema,
      }
    }
  ]
  { "tools": tools.to_json() }
}

///|
/// Run one tool for `session`. An unknown tool is a protocol error; a
/// handler that raises or outruns its deadline is a tool result with
/// `isError`, which the model reads like any other output.
async fn Server::call_tool(
  self : Server,
  session : String,
  id : Json,
  params : Json,
) -> Json {
  guard params is { "name": String(name), .. } else {
    return failure(id, InvalidParams, "tools/call needs a string `name`")
  }
  guard self.tools.get(name) is Some(tool) else {
    return failure(id, InvalidParams, "Unknown tool: \{name}")
  }
  let arguments = match params {
    { "arguments": arguments, .. } => arguments
    _ => Json::empty_object()
  }
  let outcome : (String, Bool)? = @async.with_timeout_opt(CallTimeoutMs, () => {
    try (tool.call)({ session, arguments, }) catch {
      error if @async.is_being_cancelled() => raise error
      error => ("\{error}", true)
    } noraise {
      text => (text, false)
    }
  })
  let (text, is_error) = match outcome {
    Some(outcome) => outcome
    None => ("\{name} timed out after \{CallTimeoutMs / 1000}s", true)
  }
  if is_error {
    @xlog.warn(category="mcp") <?
      {
        "event": "mcp_tool_failed",
        "tool": name,
        "session": session,
        "error": text,
      }
  }
  reply(id, {
    "content": [{ "type": "text", "text": text.to_json() }],
    "isError": is_error.to_json(),
  })
}
