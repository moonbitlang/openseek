///|
/// Acceptance confirms delivery only; engine receipts settle steering.
async fn control(
  token : String,
  session : String,
  task_id : String,
  operation : ControlOperation,
) -> ControlResult {
  let body : QueueRequest = match operation {
    Stop => return send_command(token, session, @wire.Cancel, task_id~)
    Steer(submission_id~, content~) =>
      return send_command(
        token,
        session,
        @wire.Steer(content~, submission_id=Some(submission_id)),
        task_id~,
      )
    QueueAdd(id~, content~) =>
      { task_id, action: "add", id, content: Some(content), }
    QueueEdit(id~, content~) =>
      { task_id, action: "edit", id, content: Some(content), }
    QueueWithdraw(id~) => { task_id, action: "withdraw", id, content: None, }
    QueueSteer(id~) => { task_id, action: "steer", id, content: None, }
  }
  let (response, data) = @http.request(
    CloudOrigin + "/v1/sessions/\{@uri.encode_component(session)}/queue",
    Post,
    { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
    ToJson::to_json(body).stringify(),
  ) catch {
    _ => raise @cloud_client.RequestError(Unreachable)
  }
  // Queue mutations are synchronous; a structured 409 is a definite refusal.
  if response.code != 409 {
    check_status(response.code)
  }
  let json = data.json() catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  body.decode_reply(response.code, json)
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
        NativeEvent(event) => event.session_id
        EngineFailed(session~, ..) => session
      }
      guard owner == session else {
        raise @cloud_client.RequestError(Malformed)
      }
      event(parsed)
    }
  }
}
