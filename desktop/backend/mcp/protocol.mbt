// The MCP methods this server answers, as JSON-RPC messages in and out. The
// transports provide a trusted conversation identity and write each reply
// using their own framing.
//
// Scope: the tool surface only — `initialize`, `ping`, `tools/list`, and
// `tools/call`. Resources, prompts, and server-initiated requests are not
// offered, which the `initialize` capabilities say.

///|
/// The newest legacy revision this server speaks, answered when a client
/// asks for one it does not.
const LatestLegacyProtocolVersion = "2025-11-25"

///|
/// Whether this server can speak `version`. The methods it answers are
/// unchanged across these revisions.
fn supported_legacy_version(version : String) -> Bool {
  version == LatestLegacyProtocolVersion ||
  version == "2025-06-18" ||
  version == "2025-03-26" ||
  version == "2024-11-05"
}

///|
/// The deadline for one tool handler, so a handler that never returns holds
/// a task and a connection for a bounded time rather than the app's
/// lifetime.
const CallTimeoutMs : Int32 = 150000

///|
/// Diagnostic backpressure must not hold the tool result indefinitely.
const DiagnosticWriteTimeoutMs : Int32 = 100

///|
const InvalidRequest : Int32 = -32600

///|
const MethodNotFound : Int32 = -32601

///|
const InvalidParams : Int32 = -32602

///|
fn reply(id : Json, result : Json) -> Json {
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
fn failure(id : Json, code : Int32, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id,
    "error": { "code": Json(code), "message": Json(message) },
  }
}

///|
/// Answer one inbound message for the conversation authenticated by the host.
/// `session` and `groups` come from trusted host context, never the message.
/// `None` when the message expects no reply: a notification, or a response —
/// which this server never sends, so there is nothing to match it to.
pub async fn Dispatcher::dispatch(
  self : Dispatcher,
  message : Json,
  session~ : String,
  groups~ : Array[String] = [],
) -> Json? {
  if validate_modern(message) is Some(error) {
    return Some(error)
  }
  guard message is Object(fields) else {
    // JSON-RPC answers an unidentifiable request under a null id.
    return Some(failure(null, InvalidRequest, "Invalid Request"))
  }
  guard fields.get("method") is Some(String(method_)) else {
    if fields.contains("result") || fields.contains("error") {
      return None
    }
    return Some(
      failure(
        fields.get("id").unwrap_or(null),
        InvalidRequest,
        "Invalid Request",
      ),
    )
  }
  guard fields.get("id") is Some(id) else { return None }
  let params = fields.get("params").unwrap_or(Json::empty_object())
  let modern = @wire.request_version(message) is Some(_)
  let answer = match method_ {
    "server/discover" if modern =>
      reply(id, {
        "supportedVersions": [@wire.ModernVersion],
        "capabilities": { "tools": {} },
      })
    "initialize" if modern =>
      failure(id, MethodNotFound, "Use server/discover for stateless MCP")
    "initialize" => reply(id, self.initialize_result(params))
    "ping" => reply(id, Json::empty_object())
    "tools/list" => reply(id, self.tool_list(groups))
    "tools/call" => self.call_tool(session, id, params, groups)
    _ => failure(id, MethodNotFound, "Method not found: \{method_}")
  }
  if modern && answer is { "result": Object(result), .. } {
    result["resultType"] = "complete"
    result["_meta"] = {
      "io.modelcontextprotocol/serverInfo": {
        "name": Json(ServerName),
        "version": Json(self.version),
      },
    }
  }
  Some(answer)
}

///|
fn Dispatcher::initialize_result(self : Dispatcher, params : Json) -> Json {
  let version = match params {
    { "protocolVersion": String(requested), .. } if supported_legacy_version(
        requested,
      ) => requested
    _ => LatestLegacyProtocolVersion
  }
  {
    "protocolVersion": Json(version),
    "capabilities": { "tools": Json::empty_object() },
    "serverInfo": { "name": Json(ServerName), "version": Json(self.version) },
  }
}

///|
fn Dispatcher::tool_list(self : Dispatcher, groups : Array[String]) -> Json {
  let tools : Array[Json] = [
    for _, tool in self.tools if offered(tool.name, groups) => {
      {
        "name": Json(tool.name),
        "description": Json(tool.description),
        "inputSchema": tool.input_schema,
      }
    }
  ]
  { "tools": Json(tools) }
}

///|
/// Run one tool for `session`. An unknown tool is a protocol error; a
/// handler that raises or outruns its deadline is a tool result with
/// `isError`, which the model reads like any other output.
async fn Dispatcher::call_tool(
  self : Dispatcher,
  session : String,
  id : Json,
  params : Json,
  groups : Array[String],
) -> Json {
  guard params is { "name": String(name), .. } else {
    return failure(id, InvalidParams, "tools/call needs a string `name`")
  }
  guard self.tools.get(name) is Some(tool) && offered(name, groups) else {
    return failure(id, InvalidParams, "Unknown tool: \{name}")
  }
  let arguments = match params {
    { "arguments": arguments, .. } => arguments
    _ => Json::empty_object()
  }
  async fn invoke() -> Result[Array[Content], String] {
    try (tool.call)({ session, arguments, }) catch {
      error => Err("\{error}")
    } noraise {
      content => Ok(content)
    }
  }
  let outcome = @async.with_timeout_opt(CallTimeoutMs, invoke).unwrap_or(
    Err("\{name} timed out after \{CallTimeoutMs / 1000}s"),
  )
  let (content, is_error) = match outcome {
    Ok(content) => (content, false)
    Err(error) => {
      // Diagnostics never share a protocol output stream. Logging remains
      // best effort, so a blocked or closed stderr cannot hold the tool result.
      @async.with_timeout(DiagnosticWriteTimeoutMs, () => {
        @stdio.stderr.text.write(
          Json({
            "event": "mcp_tool_failed",
            "tool": name,
            "session": session,
            "error": error,
          }).stringify() +
          "\n",
        )
      }) catch {
        _ => ()
      }
      ([Text(error)], true)
    }
  }
  reply(id, { "content": Json(content), "isError": Json(is_error) })
}

///|
/// A group is the prefix before the first underscore, or the whole name.
fn offered(name : String, groups : Array[String]) -> Bool {
  let group = if name.split_once("_") is Some((prefix, _)) {
    prefix.to_owned()
  } else {
    name
  }
  groups.is_empty() || groups.contains(group)
}
