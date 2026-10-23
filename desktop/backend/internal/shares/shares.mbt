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
/// File uploads return the failure without resending the request.
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
  on_progress(Connecting(attempt~))
  let connection = @http.Client(server_url)
  defer connection.close()
  connection.request(Post, "/v2/shares", extra_headers={
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
  let body = connection.read_all()
  if response.code == 401 {
    return @protocol.SignInRequired
  }
  if response.code == 404 {
    // The deployment may not yet expose the account-aware share endpoint.
    return @protocol.Failed(
      message="The signed-in server does not provide sharing at \{server_url}/v2/shares (HTTP 404). Sign in to a server with sharing enabled.",
    )
  }
  guard response.code is (200 | 201) else {
    // The API answers every rejection with `{ "error": message }`; only a
    // proxy answers without one. Never display an entire HTML/proxy
    // response as an error.
    let fallback = "Sharing failed (HTTP \{response.code})."
    let message = try body.json() catch {
      _ => fallback
    } noraise {
      { "error": String(detail), .. } if !detail.trim().is_empty() =>
        "Sharing failed (HTTP \{response.code}): \{detail.trim()}"
      _ => fallback
    }
    return @protocol.Failed(message~)
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
