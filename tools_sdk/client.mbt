///|
/// The canonical SDK entry point for every host-enabled tool. The host owns
/// tool names, argument validation, defaults, and callable-tool permissions;
/// enabling another tool needs no SDK release. Arguments are forwarded unchanged.
/// Reads the run-scoped
/// OPENSEEK_PTC capability. Never retries. Missing/invalid capabilities fail
/// before sending a request; cancellation propagates to the caller.
pub async fn call(name : String, arguments : Json) -> CallResult {
  let (url, token, approval_tools) = decode_handoff(
    @env.get_env_var("OPENSEEK_PTC"),
  )
  request(
    url,
    token,
    name,
    arguments,
    wait_for_approval=approval_tools.contains(name),
  )
}

///|
fn decode_handoff(
  raw : String?,
) -> (String, String, Array[String]) raise TransportError {
  guard raw is Some(raw) else {
    raise TransportError("No PTC host. Run with mbtx(ptc=true).")
  }
  let json = @json.parse(raw) catch {
    _ => raise TransportError("Invalid PTC host handoff")
  }
  guard json is { "version": 1, "url": String(url), "token": String(token), .. } else {
    raise TransportError("Invalid PTC host handoff")
  }
  let approval_tools : Array[String] = match json {
    { "approval_tools": Array(names), .. } =>
      [
        for name in names if name is String(name) => name
      ]
    _ => []
  }
  (url, token, approval_tools)
}

///|
async fn request(
  url : String,
  token : String,
  name : String,
  arguments : Json,
  wait_for_approval? : Bool = false,
  timeout_ms? : Int = 125000,
) -> CallResult {
  let request : Json = { "version": 1, "name": name, "arguments": arguments }
  // No retries: a lost response does not prove an edit failed to execute.
  async fn send() -> Json {
    let (response, body) = @http.post(url, request, headers={
      "Authorization": "Bearer \{token}",
    })
    guard response.code == 200 else {
      raise TransportError(
        "PTC transport failed (HTTP \{response.code}); execution outcome may be unknown",
      )
    }
    body.json()
  }
  // The host identifies calls that can wait for human input. Ordinary calls
  // retain their transport deadline; caller cancellation always propagates.
  let result = try {
    if wait_for_approval {
      send()
    } else {
      @async.with_timeout(timeout_ms, send)
    }
  } catch {
    TransportError::_ as error => raise error
    _ =>
      raise TransportError(
        "PTC connection failed, timed out, or returned invalid JSON; execution outcome may be unknown",
      )
  }
  decode_result(result)
}

///|
fn decode_result(result : Json) -> CallResult raise TransportError {
  guard result
    is {
      "version": 1,
      "content": String(content),
      "is_error": is_error_json,
      ..
    } else {
    raise TransportError(
      "Invalid PTC response; execution outcome may be unknown",
    )
  }
  let is_error = match is_error_json {
    True => true
    False => false
    _ => raise TransportError("Invalid PTC error flag")
  }
  let data = match result {
    { "data": data, .. } => Some(data)
    _ => None
  }
  { content, is_error, data, }
}
