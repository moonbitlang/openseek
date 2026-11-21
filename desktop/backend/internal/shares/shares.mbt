///|
/// Capture the share content and multipart boundary before upload. Conversation
/// retries reuse that snapshot; file snapshots retain their original bytes.
struct Snapshot {
  key : String
  parts : Array[(@http.Headers, String)]
  file : (String, Bytes)?
}

///|
/// Why content cannot become a share request at all; no upload starts.
pub(all) suberror ShareError {
  EmptyTitle
  Oversized
  InvalidFilename
}

///|
/// The text the export dialog shows for each refusal.
pub impl Show for ShareError with fn output(self, logger) {
  logger.write_string(
    match self {
      InvalidFilename => "The filename cannot contain line breaks."
      EmptyTitle => "The conversation title must not be empty."
      Oversized =>
        "This export exceeds the 20 MiB share limit. Use Download instead."
    },
  )
}

///|
pub extend ShareError with Show::{to_string, output}

///|
/// All fields are UTF-8 multipart bodies, never interpolated into headers.
/// The limit includes framing, matching POST /v2/shares on openseek-api.
pub fn Snapshot::Snapshot(
  title~ : String,
  html~ : String,
  json~ : String,
  key~ : String,
) -> Snapshot raise ShareError {
  Snapshot::conversation(title~, html~, json~, key~, feedback=None)
}

///|
fn Snapshot::conversation(
  title~ : String,
  html~ : String,
  json~ : String,
  key~ : String,
  feedback~ : Json?,
) -> Snapshot raise ShareError {
  // The API limits the title to 1024 UTF-8 bytes, and a generated title may
  // be the entire first prompt. A UTF-16 code unit encodes to at most three
  // UTF-8 bytes, so 341 units can never exceed the limit; the slice keeps
  // surrogate pairs whole. The HTML and JSON retain the complete records.
  let title = title.trim()[:1024 / 3].to_owned()
  guard !title.is_empty() else { raise EmptyTitle }
  let parts : Array[(@http.Headers, String)] = [
    ({ "Content-Disposition": "form-data; name=\"title\"" }, title),
    (
      {
        "Content-Disposition": "form-data; name=\"html\"; filename=\"conversation.html\"",
        "Content-Type": "text/html; charset=utf-8",
      },
      html,
    ),
    (
      {
        "Content-Disposition": "form-data; name=\"json\"; filename=\"conversation.json\"",
        "Content-Type": "application/json; charset=utf-8",
      },
      json,
    ),
  ]
  if feedback is Some(metadata) {
    parts.push(
      (
        {
          "Content-Disposition": "form-data; name=\"metadata\"",
          "Content-Type": "application/json",
        },
        metadata.stringify(),
      ),
    )
  }
  // Include boundaries, headers, and CRLFs without assembling the full body.
  let mut size = key.length() + 6
  for (headers, text) in parts {
    size += key.length() + 8
    for name, value in headers {
      size += @utf8.encode("\{name.0}: \{value}\r\n").length()
    }
    let mut offset = 0
    while offset < text.length() {
      let chunk = text[offset:(offset + 4096).min(text.length())]
      size += @utf8.encode(chunk).length()
      guard size <= 20 * 1024 * 1024 else { raise Oversized }
      offset += chunk.length()
    }
  }
  guard size <= 20 * 1024 * 1024 else { raise Oversized }
  { key, parts, file: None, }
}

///|
/// The caller captures its own account credential with the source snapshot.
/// Never consult a device token or a newer login while retrying publication.
/// Conversation exports retry a lost attempt with the same bytes and key.
/// File uploads return ambiguous failures without resending the request.
pub async fn Snapshot::publish(
  self : Snapshot,
  server_url~ : String,
  token~ : String,
  timeout_ms~ : Int32 = 240_000,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> @protocol.SessionShareReply {
  let attempt = async fn(attempt : Int32) {
    @async.with_timeout(timeout_ms, () => {
      self.send(server_url~, token~, attempt~, on_progress~)
    })
  }
  attempt(1) catch {
    error =>
      try {
        if self.file is None {
          attempt(2)
        } else {
          raise error
        }
      } catch {
        @async.TimeoutError =>
          @protocol.Failed(
            message="The share request timed out. Please try again.",
          )
        error => @protocol.Failed(message="The share request failed: \{error}")
      }
  }
}

///|
async fn Snapshot::send(
  self : Snapshot,
  server_url~ : String,
  token~ : String,
  attempt~ : Int32,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  let (code, body) = self.post(
    "/v2/shares",
    server_url~,
    token~,
    attempt~,
    on_progress~,
  )
  if code == 401 {
    return @protocol.SignInRequired
  }
  if code == 404 {
    // The deployment may not yet expose the account-aware share endpoint.
    return @protocol.Failed(
      message="The signed-in server does not provide sharing at \{server_url}/v2/shares (HTTP 404). Sign in to a server with sharing enabled.",
    )
  }
  guard code == 201 || code == 200 else {
    return @protocol.Failed(message=upload_error("Sharing", code, body))
  }
  let invalid = "The share server did not return a valid share link."
  try body.json() catch {
    _ => @protocol.Failed(message=invalid)
  } noraise {
    { "url": String(url), .. } => @protocol.Shared(url~)
    _ => @protocol.Failed(message=invalid)
  }
}

///|
async fn Snapshot::post(
  self : Snapshot,
  path : String,
  server_url~ : String,
  token~ : String,
  attempt~ : Int32 = 1,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> (Int32, &@io.Data) {
  on_progress(Connecting(attempt~))
  let connection = @http.Client(server_url)
  defer connection.close()
  connection.request(Post, path, extra_headers={
    "Authorization": "Bearer \{token}",
    "Idempotency-Key": self.key,
    "Content-Type": "multipart/form-data; boundary=\{self.key}",
  })
  on_progress(Uploading(attempt~))
  self.write_body(connection)
  connection.flush()
  // Fetch may only begin sending here; this stage makes no byte-completion claim.
  on_progress(Waiting(attempt~))
  let response = connection.end_request()
  (response.code, connection.read_all())
}

///|
/// Only the API's error field is suitable for display. A proxy can return HTML.
fn upload_error(action : String, code : Int32, body : &@io.Data) -> String {
  let detail = body.json() catch { _ => null }
  match detail {
    { "error": String(message), .. } if !message.is_blank() =>
      "\{action} failed (HTTP \{code}): \{message.trim()}"
    _ => "\{action} failed (HTTP \{code})."
  }
}

///|
pub async fn submit_feedback(
  title~ : String,
  html~ : String,
  json~ : String,
  key~ : String,
  metadata~ : Json,
  server_url~ : String,
  token~ : String,
) -> @protocol.SessionFeedbackReply {
  let snapshot = Snapshot::conversation(
    title~,
    html~,
    json~,
    key~,
    feedback=Some(metadata),
  )
  // Feedback has no implicit retry: a lost response can follow a successful write.
  let (code, body) = @async.with_timeout(240_000, () => {
    snapshot.post("/v1/feedback", server_url~, token~)
  }) catch {
    @async.TimeoutError =>
      return Failed(
        message="The feedback request timed out. Delivery could not be confirmed.",
      )
    error => return Failed(message="The feedback request failed: \{error}")
  }
  match code {
    201 => {
      let receipt : @protocol.FeedbackReceipt = @json.from_json(body.json()) catch {
        _ => return Failed(message="Invalid feedback receipt.")
      }
      Submitted(id=receipt.id)
    }
    401 => SignInRequired
    _ => Failed(message=upload_error("Feedback", code, body))
  }
}

///|
async fn Snapshot::write_body(self : Snapshot, target : &@io.Writer) -> Unit {
  let form = @multipart.Writer(target, boundary=self.key)
  for (headers, text) in self.parts {
    form.write_part(headers~, target => {
      let mut offset = 0
      while offset < text.length() {
        let chunk = text[offset:(offset + 4096).min(text.length())]
        target.write(chunk)
        offset += chunk.length()
      }
    })
  }
  if self.file is Some((name, bytes)) {
    let name = name
      .replace_all(old="\\", new="\\\\")
      .replace_all(old="\"", new="\\\"")
    form.write_part(
      headers={
        "Content-Disposition": "form-data; name=\"file\"; filename=\"\{name}\"",
        "Content-Type": "application/octet-stream",
      },
      target => target.write(bytes),
    )
  }
  form.finish()
}

///|
/// File content is already captured by its host. Unlike conversation exports,
/// file uploads have no client preview limit and are never retried implicitly.
pub fn Snapshot::file(
  name~ : String,
  bytes~ : Bytes,
  key~ : String,
) -> Snapshot raise ShareError {
  guard !name.contains("\r") && !name.contains("\n") else {
    raise InvalidFilename
  }
  {
    key,
    parts: [({ "Content-Disposition": "form-data; name=\"title\"" }, name)],
    file: Some((name, bytes)),
  }
}
