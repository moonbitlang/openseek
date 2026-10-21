///|
pub using @cloud_client {CloudOrigin}

///|
using @cloud_client {check_status, request}

///|
async fn list_sessions(token : String) -> Array[Session] {
  decode_sessions(request(CloudOrigin, "/v1/sessions", Get, token~))
}

///|
async fn delete_session(token : String, session : String) -> Unit {
  let (response, _) = @http.request(
    CloudOrigin + "/v1/sessions/\{@uri.encode_component(session)}",
    Delete,
    { "Authorization": "Bearer " + token },
    "",
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  // Deletion is idempotent, and a successful 204 has no JSON body.
  if response.code != 404 {
    check_status(response.code)
  }
}

///|
async fn load_history(token : String, session : String) -> History {
  decode_history(
    request(
      CloudOrigin,
      "/v1/sessions/\{@uri.encode_component(session)}/messages",
      Get,
      token~,
    ),
  )
}

///|
async fn edit_session(
  token : String,
  session : String,
  edit : SessionEdit,
) -> Unit {
  let (response, _) = @http.request(
    CloudOrigin + "/v1/sessions/\{@uri.encode_component(session)}",
    Patch,
    { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
    ToJson::to_json(edit).stringify(),
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  // Metadata updates return an empty 204, not a JSON document.
  if response.code == 409 {
    raise @cloud_client.RequestError(Http(409))
  }
  check_status(response.code)
}

///|
/// Async HTTP's JS client uses fetch, exposing its response stream. Reading
/// complete UTF-8 lines buffers arbitrary network and codepoint boundaries.
/// Cookies use fetch's default same-origin policy: none are sent to Cloud.
async fn send_message(
  token : String,
  session : String,
  content : @wire.Content,
  stream : StreamLease,
  event : (Event) -> Unit,
) -> Unit {
  let client = @http.Client(CloudOrigin, headers={
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
  }) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  defer client.close()
  guard stream.active else { return }
  stream.client = Some(client)
  let body : Json = { "content": content.to_json() }
  let response = client.post(
    "/v1/sessions/\{@uri.encode_component(session)}/messages",
    body.stringify(),
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  if response.code == 503 {
    let message = client.read_all().text() catch {
        _ => raise @cloud_client.RequestError(Unreachable)
      }
    if message.trim() == "server model credentials are not configured" {
      raise @cloud_client.RequestError(ServiceNotConfigured)
    }
  }
  check_status(response.code)
  let parser = @cloud_client.SseParser::new()
  while stream.active {
    let line = client.read_until("\n") catch {
      _ => raise @cloud_client.RequestError(Unreachable)
    }
    guard line is Some(line) else { break }
    if parser.line(line) is Some((_, data)) {
      let json = @json.parse(data) catch {
        _ => raise @cloud_client.RequestError(Malformed)
      }
      event(decode_event(json))
    }
  }
}

///|
/// Capture the server's standalone export from the original engine records.
pub async fn export_snapshot(
  token : String,
  session : String,
) -> @protocol.SessionSnapshot {
  let snapshot = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/export",
    Get,
    token~,
  ) catch {
    @cloud_client.RequestError(Busy) =>
      raise @cloud_client.RequestError(ExportUnavailable)
    error => raise error
  }
  @json.from_json(snapshot) catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
}

///|
/// Publish server-captured engine records; never download them for an upload.
pub async fn share(
  token : String,
  session : String,
  idempotency_key : String,
) -> String {
  let response = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/share",
    Post,
    token~,
    body={ "idempotency_key": idempotency_key },
  ) catch {
    @cloud_client.RequestError(Busy) =>
      raise @cloud_client.RequestError(ExportUnavailable)
    error => raise error
  }
  guard response is { "url": String(url), .. } && !url.is_empty() else {
    raise @cloud_client.RequestError(Malformed)
  }
  url
}
