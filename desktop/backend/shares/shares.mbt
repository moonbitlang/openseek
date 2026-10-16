///|
/// Why a conversation cannot become a share request at all; no upload starts.
pub(all) suberror ShareError {
  EmptyTitle
}

///|
/// The text the export dialog shows for each refusal.
pub impl Show for ShareError with fn output(self, logger) {
  logger.write_string(
    match self {
      EmptyTitle => "The conversation title must not be empty."
    },
  )
}

///|
pub extend ShareError with Show::{to_string, output}

///|
/// Stream already-rendered export files to their issuer. Each attempt reads
/// the same HTML and JSON strings. A lost response or transport
/// failure is retried once with the same multipart boundary and idempotency key.
/// Cancellation closes the active connection and does not start a retry.
pub async fn publish(
  title~ : String,
  files : @engine.ConversationExport,
  server_url~ : String,
  token~ : String,
  timeout_ms~ : Int32 = 240_000,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> @protocol.SessionShareReply {
  publish_content(
    title~,
    { html: files.html, json: files.json, },
    server_url~,
    token~,
    timeout_ms~,
    on_progress~,
  )
}

///|
/// Upload content captured on a working host using this desktop's credentials.
pub async fn publish_content(
  title~ : String,
  files : @protocol.SessionExportContent,
  server_url~ : String,
  token~ : String,
  timeout_ms~ : Int32 = 240_000,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> @protocol.SessionShareReply {
  // Preserve the API's title limit without truncating the exported records.
  let title = title.trim()[:1024 / 3].to_owned()
  guard !title.is_empty() else { raise EmptyTitle }
  let mut headers : @http.Headers? = None
  let attempt = async fn(attempt : Int32) {
    @async.with_timeout(timeout_ms, () => {
      on_progress(Connecting(attempt~))
      let connection = @http.Client(server_url)
      defer connection.close()
      let request_headers = match headers {
        Some(headers) => headers
        None => {
          let form = @multipart.FormWriter(connection)
          let generated : @http.Headers = {
            "Authorization": "Bearer \{token}",
            "Idempotency-Key": form.boundary(),
            "Content-Type": form.content_type(),
          }
          headers = Some(generated)
          generated
        }
      }
      send(
        connection,
        title~,
        files,
        server_url~,
        headers=request_headers,
        attempt~,
        on_progress~,
      )
    })
  }
  attempt(1) catch {
    @multipart.MultipartError(_) as error => raise error
    _ =>
      attempt(2) catch {
        @multipart.MultipartError(_) as error => raise error
        @async.TimeoutError =>
          @protocol.Failed(
            message="The share request timed out. Please try again.",
          )
        error => @protocol.Failed(message="The share request failed: \{error}")
      }
  }
}

///|
async fn send(
  connection : @http.Client,
  title~ : String,
  files : @protocol.SessionExportContent,
  server_url~ : String,
  headers~ : @http.Headers,
  attempt~ : Int32,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  connection.request(Post, "/v1/shares", extra_headers=headers)
  // FormWriter chooses the boundary once; Writer lets retries reuse it on a
  // fresh connection without retaining the encoded request body.
  let form = @multipart.Writer(connection, boundary=headers["Idempotency-Key"])
  let total = files.html.length().to_int64() + files.json.length().to_int64()
  let mut written = 0L
  let mut last_percent = 0
  on_progress(Uploading(attempt~, percent=0))
  let advance = async fn(units : Int32) {
    written += units.to_int64()
    let percent = if total == 0L {
      100
    } else {
      (written * 100L / total).to_int()
    }
    if percent > last_percent {
      connection.flush()
      last_percent = percent
      on_progress(Uploading(attempt~, percent~))
    }
  }
  form.write_part(
    headers={ "Content-Disposition": "form-data; name=\"title\"" },
    target => target.write(title),
  )
  form.write_part(
    headers={
      "Content-Disposition": "form-data; name=\"html\"; filename=\"conversation.html\"",
      "Content-Type": "text/html; charset=utf-8",
    },
    target => write_text(target, files.html, advance),
  )
  form.write_part(
    headers={
      "Content-Disposition": "form-data; name=\"json\"; filename=\"conversation.json\"",
      "Content-Type": "application/json; charset=utf-8",
    },
    target => write_text(target, files.json, advance),
  )
  form.finish()
  connection.flush()
  on_progress(Waiting(attempt~))
  let response = connection.end_request()
  let body = connection.read_all()
  if response.code == 401 {
    return @protocol.SignInRequired
  }
  if response.code == 404 {
    // A device login can still point at a deployment without share routes.
    return @protocol.Failed(
      message="The signed-in server does not provide sharing at \{server_url}/v1/shares (HTTP 404). Sign in to a server with sharing enabled.",
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
// Encode bounded slices, keeping surrogate pairs whole. The existing export
// strings are retained for retries, without buffering another multipart body.
async fn write_text(
  target : &@io.Writer,
  text : String,
  advance : async (Int32) -> Unit,
) -> Unit {
  let mut offset = 0
  while offset < text.length() {
    let chunk = text[offset:(offset + 4096).min(text.length())]
    target.write(chunk)
    offset += chunk.length()
    advance(chunk.length())
  }
}
