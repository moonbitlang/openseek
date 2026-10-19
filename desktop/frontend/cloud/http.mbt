///|
const CloudOrigin = "https://cloud.moonbitlang.cn"

///|
fn check_status(status : Int32) -> Unit raise CloudError {
  match status {
    200 | 201 | 204 => ()
    401 => raise CloudError(Unauthorized)
    409 => raise CloudError(Busy)
    _ => raise CloudError(Http(status))
  }
}

///|
async fn request(
  origin : String,
  path : String,
  method_ : @http.RequestMethod,
  token? : String,
  body? : Json,
) -> Json {
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": "application/json",
  }
  if token is Some(token) {
    headers["Authorization"] = "Bearer " + token
  }
  let (response, data) = @http.request(
    origin + path,
    method_,
    headers,
    body.map_or("", body => body.stringify()),
  ) catch {
    _ => raise CloudError(Unreachable)
  }
  check_status(response.code)
  data.json() catch {
    _ => raise CloudError(Malformed)
  }
}

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
    _ => raise CloudError(Unreachable)
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
/// Async HTTP's JS client uses fetch, exposing its response stream. Reading
/// complete UTF-8 lines buffers arbitrary network and codepoint boundaries.
/// Cookies use fetch's default same-origin policy: none are sent to Cloud.
async fn send_message(
  token : String,
  session : String,
  content : String,
  stream : StreamLease,
  event : (Event) -> Unit,
) -> Unit {
  let client = @http.Client(CloudOrigin, headers={
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
  }) catch {
    _ => raise CloudError(Unreachable)
  }
  defer client.close()
  guard stream.active else { return }
  stream.client = Some(client)
  let body : Json = { "content": Json(content) }
  let response = client.post(
    "/v1/sessions/\{@uri.encode_component(session)}/messages",
    body.stringify(),
  ) catch {
    _ => raise CloudError(Unreachable)
  }
  if response.code == 503 {
    let message = client.read_all().text() catch {
        _ => raise CloudError(Unreachable)
      }
    if message.trim() == "server model credentials are not configured" {
      raise CloudError(ServiceNotConfigured)
    }
  }
  check_status(response.code)
  let parser = SseParser::new()
  while stream.active {
    let line = client.read_until("\n") catch {
      _ => raise CloudError(Unreachable)
    }
    guard line is Some(line) else { break }
    if parser.line(line) is Some(data) {
      let json = @json.parse(data) catch { _ => raise CloudError(Malformed) }
      event(decode_event(json))
    }
  }
}

///|
/// SSE data fields are joined until the empty dispatch line. Comments,
/// event names and IDs do not supply message content.
priv struct SseParser {
  mut data : Array[String]
}

///|
fn SseParser::new() -> SseParser {
  { data: [], }
}

///|
fn SseParser::line(self : SseParser, raw : String) -> String? {
  let line = raw.strip_suffix("\r").unwrap_or(raw.view()).to_owned()
  if line.is_empty() {
    let data = self.data
    self.data = []
    return if data.is_empty() { None } else { Some(data.join("\n")) }
  }
  if line.strip_prefix("data:") is Some(value) {
    self.data.push(value.strip_prefix(" ").unwrap_or(value).to_owned())
  }
  None
}

///|
/// Export the same committed visible history served to the conversation UI.
/// Sequence numbers describe this exported projection, not engine checkpoints.
pub async fn export_record(
  token : String,
  session : String,
) -> Result[String, Failure] {
  Ok(history_record(load_history(token, session))) catch {
    CloudError(error) => Err(error)
    _ => Err(Unreachable)
  }
}

///|
fn history_record(history : History) -> String {
  let text = StringBuilder()
  for index, record in history.messages {
    let item : Json = normalized_item(record.kind, record.data).unwrap_or_else(() => {
      if record.kind == "task_finished" {
        let completed = record.data is { "status": "completed", .. }
        {
          "kind": "terminal",
          "payload": {
            "kind": if completed {
              "finished"
            } else {
              "failed"
            },
            "message": if completed {
              ""
            } else {
              record.data.stringify()
            },
          },
        }
      } else {
        {
          "kind": "runtime_notice",
          "payload": { "content": record.kind + ": " + record.data.stringify() },
        }
      }
    })
    let line : Json = {
      "sequence": index + 1,
      "ts": record.created_at,
      "item": item,
    }
    text.write_string(line.stringify())
    text.write_char('\n')
  }
  text.to_string()
}

///|
/// Publish server-captured visible history; never download it for an upload.
pub async fn share(
  token : String,
  session : String,
  idempotency_key : String,
) -> Result[String, Failure] {
  try {
    let response = request(
      CloudOrigin,
      "/v1/sessions/\{@uri.encode_component(session)}/share",
      Post,
      token~,
      body={ "idempotency_key": idempotency_key },
    )
    guard response is { "url": String(url), .. } && !url.is_empty() else {
      raise CloudError(Malformed)
    }
    Ok(url)
  } catch {
    CloudError(error) => Err(error)
    _ => Err(Unreachable)
  }
}
