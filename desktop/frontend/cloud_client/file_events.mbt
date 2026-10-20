///|
priv enum WorkspaceEvent {
  Invalidated
}

///|
/// The current invalidation payload is an object with no required fields.
/// Unknown fields are ignored so adding metadata does not break subscribers.
impl FromJson for WorkspaceEvent with fn from_json(json, path) {
  guard json is Object(_) else {
    raise @json.JsonDecodeError(
      (path, "expected workspace invalidation object"),
    )
  }
  Invalidated
}

///|
fn workspace_invalidated(
  event : String,
  data : String,
) -> Bool raise RequestError {
  guard event == "workspace_invalidated" else { return false }
  let json = @json.parse(data) catch { _ => raise RequestError(Malformed) }
  let _ : WorkspaceEvent = @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
  true
}

///|
/// Watch one connection. The owner closes the exposed client on unload and
/// decides whether to reconnect after EOF or failure. The active guard also
/// fences a response that arrives after the owner has unloaded.
pub async fn watch_files(
  token : String,
  session : String,
  opened : (@http.Client) -> Unit,
  active : () -> Bool,
  invalidated : () -> Unit,
) -> Unit {
  let client = @http.Client(CloudOrigin, headers={
    "Authorization": "Bearer " + token,
    "Accept": "text/event-stream",
  }) catch {
    _ => raise RequestError(Unreachable)
  }
  defer client.close()
  guard active() else { return }
  opened(client)
  guard active() else { return }
  let response = client.get(
    "/v1/sessions/\{@uri.encode_component(session)}/files/events",
  ) catch {
    _ => raise RequestError(Unreachable)
  }
  guard active() else { return }
  check_status(response.code)
  let parser = SseParser::new()
  while active() {
    let line = client.read_until("\n") catch {
      _ => raise RequestError(Unreachable)
    }
    guard active() else { break }
    guard line is Some(line) else { break }
    if parser.line(line) is Some((event, data)) &&
      workspace_invalidated(event, data) {
      invalidated()
    }
  }
}
