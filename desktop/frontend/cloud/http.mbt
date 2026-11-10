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
/// A page is one turn; `HistoryWindow` indexes pages by turn offset.
const HistoryPageSize = 1

///|
/// A latest-page read validated by its cached ETag.
priv enum LatestHistory {
  Changed(History)
  Unchanged(String)
}

///|
async fn load_history(
  token : String,
  session : String,
  etag : String?,
  offset? : Int32,
) -> LatestHistory {
  let headers : @http.Headers = { "Authorization": "Bearer " + token }
  if etag is Some(etag) {
    headers["If-None-Match"] = etag
  }
  let path = CloudOrigin +
    "/v1/sessions/\{@uri.encode_component(session)}/messages?limit=\{HistoryPageSize}"
  let path = offset.map_or(path, offset => path + "&offset=\{offset}")
  let (response, body) = @http.get(path, headers~) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  let validator = response.headers.get("ETag")
  if response.code == 304 && etag is Some(sent) {
    return Unchanged(validator.unwrap_or(sent))
  }
  check_status(response.code)
  let json = body.json() catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  Changed({ ..decode_history(json), etag: validator, })
}

///|
async fn load_latest_history(
  token : String,
  session : String,
  etag : String?,
  epoch : Int32,
  request : Int32,
) -> Msg {
  match load_history(token, session, etag) {
    Changed(history) => Loaded(epoch, session, request, history)
    Unchanged(etag) => HistoryUnchanged(epoch, session, request, etag)
  }
}

///|
/// Read one earlier turn. No validator is sent, so the reply is always a page.
async fn load_turn_history(
  token : String,
  session : String,
  offset : Int32,
) -> History {
  guard load_history(token, session, None, offset~) is Changed(history) else {
    raise @cloud_client.RequestError(Malformed)
  }
  history
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

///|
/// Create a Cloud chat from an export. The service downloads share links
/// itself, from its account origin, and answers 201 with the new session id.
/// Rejections the user can act on (wrong origin, missing or expired share,
/// unreachable share host) carry the service's explanation.
pub async fn import_session(
  token : String,
  source : @protocol.SessionImportSource,
) -> @protocol.SessionImportReply {
  let (response, data) = @http.request(
    CloudOrigin + "/v1/sessions/import",
    Post,
    { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
    ({ "source": source.to_json() } : Json).stringify(),
  ) catch {
    _ => return Failed(@cloud_client.Failure::Unreachable.label())
  }
  if response.code is (400 | 404 | 410 | 502) {
    let message = data.text() catch { _ => "" }
    if !message.trim().is_empty() {
      return Failed(message.trim().to_owned())
    }
  }
  check_status(response.code) catch {
    @cloud_client.RequestError(failure) => return Failed(failure.label())
  }
  let json = data.json() catch {
    _ => return Failed(@cloud_client.Failure::Malformed.label())
  }
  guard response.code == 201 &&
    json is { "id": String(id), .. } &&
    !id.is_empty() else {
    return Failed(@cloud_client.Failure::Malformed.label())
  }
  Success(id)
}
