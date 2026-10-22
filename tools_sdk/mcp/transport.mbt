///|
/// A request to the MCP host, which hands its capability over in
/// `OPENSEEK_MCP`. Both are answered with the same result envelope.
priv enum Request {
  /// An MCP server's tool.
  Call(server~ : String, tool~ : String, arguments~ : Json)
  /// One reply's worth of catalog items from `cursor`, the start when absent.
  List(cursor~ : Int32?)
}

///|
/// The decoded result envelope
/// `{"version":1,"content","is_error","data"?,"images"?}`. `images` are the
/// paths of files the MCP host saved a call's images in.
priv struct Reply {
  content : String
  is_error : Bool
  data : Json?
  images : Array[String]
}

///|
/// The run-scoped capability decoded from `OPENSEEK_MCP`.
priv struct Capability {
  url : String
  token : String
}

///|
const NO_HOST = "No MCP host: this run has no MCP servers configured."

///|
/// Reads the run-scoped `OPENSEEK_MCP` capability and sends one request.
/// Never retries. A missing or invalid capability fails before sending;
/// cancellation propagates to the caller.
async fn send(request : Request) -> Reply raise TransportError {
  let capability = decode_handoff(@env.get_env_var("OPENSEEK_MCP"))
  post(capability.url, capability.token, encode(request))
}

///|
fn decode_handoff(raw : String?) -> Capability raise TransportError {
  guard raw is Some(raw) else { raise TransportError(NO_HOST) }
  let json = @json.parse(raw) catch {
    _ => raise TransportError("Invalid MCP host handoff")
  }
  guard json is { "version": 1, "url": String(url), "token": String(token), .. } else {
    raise TransportError("Invalid MCP host handoff")
  }
  { url, token, }
}

///|
fn encode(request : Request) -> Json {
  match request {
    Call(server~, tool~, arguments~) =>
      {
        "version": 1,
        "call": { "server": server, "tool": tool, "arguments": arguments },
      }
    List(cursor~) => {
      let list = Map([])
      if cursor is Some(cursor) {
        list["cursor"] = Json(cursor)
      }
      { "version": 1, "list": Json::object(list) }
    }
  }
}

///|
/// MCP calls never wait for approval, so every request has the deadline that
/// covers the host's 120-second tool deadline.
async fn post(
  url : String,
  token : String,
  request : Json,
  timeout_ms~ : Int32 = 125000,
) -> Reply raise TransportError {
  // No retries: a lost response does not prove a call failed to execute.
  async fn send() -> Json {
    let (response, body) = @http.post(url, request, headers={
      "Authorization": "Bearer \{token}",
    })
    guard response.code == 200 else {
      raise TransportError(
        "MCP host transport failed (HTTP \{response.code}); execution outcome may be unknown",
      )
    }
    body.json()
  }
  // Caller cancellation always propagates.
  let result = @async.with_timeout(timeout_ms, send) catch {
    TransportError(_) as error => raise error
    _ =>
      raise TransportError(
        "MCP host connection failed, timed out, or returned invalid JSON; execution outcome may be unknown",
      )
  }
  decode_reply(result)
}

///|
fn decode_reply(result : Json) -> Reply raise TransportError {
  guard result
    is {
      "version": 1,
      "content": String(content),
      "is_error": is_error_json,
      ..
    } else {
    raise TransportError(
      "Invalid MCP host response; execution outcome may be unknown",
    )
  }
  let is_error = match is_error_json {
    True => true
    False => false
    _ => raise TransportError("Invalid MCP host error flag")
  }
  let data = match result {
    { "data": data, .. } => Some(data)
    _ => None
  }
  let images = match result {
    { "images": Array(paths), .. } => {
      let images = []
      for path in paths {
        guard path is String(path) else {
          raise TransportError("Invalid MCP host image list")
        }
        images.push(path)
      }
      images
    }
    { "images": _, .. } => raise TransportError("Invalid MCP host image list")
    _ => []
  }
  { content, is_error, data, images, }
}
