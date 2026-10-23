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
/// The response acknowledges delivery only. The existing session subscription
/// owns engine receipts and task lifecycle; this request never retries.
async fn send_command(
  token : String,
  session : String,
  command : @wire.Command,
  task_id? : String,
  api_key? : String,
) -> ControlResult {
  let body : CommandRequest = { command, task_id, api_key, }
  let (response, data) = @http.request(
    CloudOrigin + "/v1/sessions/\{@uri.encode_component(session)}/commands",
    Post,
    { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
    ToJson::to_json(body).stringify(),
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  if response.code == 503 {
    let message = data.text()
    if message.trim() == "server model credentials are not configured" {
      raise @cloud_client.RequestError(ServiceNotConfigured)
    }
  }
  if response.code == 409 {
    // A refusal is definitive regardless of its body encoding.
    let body = data.text()
    let json : Json = @json.parse(body) catch { _ => null }
    let reason = match json {
      { "error": String(error), .. } => error.trim()
      _ => body.trim()
    }
    return Rejected(
      if reason.is_empty() {
        "HTTP 409"
      } else {
        reason.to_owned()
      },
    )
  }
  if response.code != 202 {
    check_status(response.code)
  }
  let json = data.json() catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  if response.code == 202 && json is { "accepted": True, .. } {
    Accepted
  } else {
    raise @cloud_client.RequestError(Malformed)
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
/// Publish a service-captured conversation or file; never download it for an upload.
pub async fn share(
  token : String,
  session : String,
  idempotency_key : String,
  path? : String,
) -> String {
  let response = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/" +
    (if path is Some(_) { "files/share" } else { "share" }),
    Post,
    token~,
    body=match path {
      Some(path) => { "path": path, "idempotency_key": idempotency_key }
      None => { "idempotency_key": idempotency_key }
    },
  ) catch {
    @cloud_client.RequestError(Busy) if path is None =>
      raise @cloud_client.RequestError(ExportUnavailable)
    error => raise error
  }
  guard response is { "url": String(url), .. } && !url.is_empty() else {
    raise @cloud_client.RequestError(Malformed)
  }
  url
}
