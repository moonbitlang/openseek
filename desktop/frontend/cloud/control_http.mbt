///|
/// Acceptance confirms delivery only; engine receipts settle steering.
async fn control(
  token : String,
  session : String,
  task_id : String,
  operation : ControlOperation,
) -> ControlResult {
  let endpoint = match operation {
    Stop => "stop"
    Steer(..) => "steer"
    _ => "queue"
  }
  let body : ControlRequest = { task_id, operation, }
  let (response, data) = @http.request(
    CloudOrigin + "/v1/sessions/\{@uri.encode_component(session)}/" + endpoint,
    Post,
    { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
    ToJson::to_json(body).stringify(),
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  // 202 is control acceptance, and a structured 409 is a definite refusal.
  if !(response.code is (202 | 409)) {
    check_status(response.code)
  }
  let json = data.json() catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  operation.decode_reply(response.code, task_id, json)
}

///|
async fn read_control(token : String, session : String) -> ControlSnapshot {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/control",
    Get,
    token~,
  )
  let snapshot : ControlSnapshot = @json.from_json(json) catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  guard snapshot.session_id == session else {
    raise @cloud_client.RequestError(Malformed)
  }
  snapshot
}

///|
/// Observing or closing this stream does not stop the server task.
async fn watch_control(
  token : String,
  session : String,
  stream : StreamLease,
  event : (ControlStreamEvent) -> Unit,
) -> Unit {
  let client = @http.Client(CloudOrigin, headers={
    "Authorization": "Bearer " + token,
    "Accept": "text/event-stream",
  }) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  defer client.close()
  guard stream.active else { return }
  stream.client = Some(client)
  let response = client.get(
    "/v1/sessions/\{@uri.encode_component(session)}/events",
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  guard stream.active else { return }
  check_status(response.code)
  let parser = @cloud_client.SseParser::new()
  while stream.active {
    let line = client.read_until("\n") catch {
      _ => raise @cloud_client.RequestError(Unreachable)
    }
    guard stream.active else { break }
    guard line is Some(line) else { break }
    if parser.line(line) is Some((name, data)) {
      let json = @json.parse(data) catch {
        _ => raise @cloud_client.RequestError(Malformed)
      }
      let parsed = decode_control_event(name, json)
      let owner = match parsed {
        Snapshot(snapshot) => snapshot.session_id
        EngineEvent(event) => event.session_id
      }
      guard owner == session else {
        raise @cloud_client.RequestError(Malformed)
      }
      event(parsed)
    }
  }
}
