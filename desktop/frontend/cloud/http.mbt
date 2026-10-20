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
/// Export the same committed visible history served to the conversation UI.
/// Sequence numbers describe this exported projection, not engine checkpoints.
pub async fn export_record(token : String, session : String) -> String {
  history_record(load_history(token, session))
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
) -> String {
  let response = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/share",
    Post,
    token~,
    body={ "idempotency_key": idempotency_key },
  )
  guard response is { "url": String(url), .. } && !url.is_empty() else {
    raise @cloud_client.RequestError(Malformed)
  }
  url
}
