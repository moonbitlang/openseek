///|
/// One immutable upload: a retry must retain both the rendered conversation
/// and its idempotency key, even while the live conversation changes. The
/// 64-character hex key doubles as the multipart boundary, which RFC 2046
/// section 5.1.1 limits to 70 characters.
struct Snapshot {
  key : String
  body : Bytes
}

///|
/// Why a conversation cannot become a share request at all; no upload starts.
pub(all) suberror ShareError {
  EmptyTitle
  EntropyUnavailable
  Oversized
}

///|
/// The text the export dialog shows for each refusal.
pub impl Show for ShareError with fn output(self, logger) {
  logger.write_string(
    match self {
      EmptyTitle => "The conversation title must not be empty."
      EntropyUnavailable =>
        "Could not create a secure share request. Please try again."
      Oversized =>
        "This export exceeds the 20 MiB share limit. Use Download instead."
    },
  )
}

///|
pub extend ShareError with Show::{to_string, output}

///|
/// All fields are UTF-8 multipart bodies, never interpolated into headers.
/// The limit includes framing, matching POST /v1/shares on openseek-api.
pub fn Snapshot::Snapshot(
  title~ : String,
  html~ : String,
  json~ : String,
) -> Snapshot raise ShareError {
  // The API limits the title to 1024 UTF-8 bytes, and a generated title may
  // be the entire first prompt. A UTF-16 code unit encodes to at most three
  // UTF-8 bytes, so 341 units can never exceed the limit; clamped_view keeps
  // surrogate pairs whole. The HTML and JSON retain the complete records.
  let title = title.trim().clamped_view(end=1024 / 3).to_owned()
  guard !title.is_empty() else { raise EmptyTitle }
  guard @entropy.random_hex(32) is Some(key) else { raise EntropyUnavailable }
  let body = @utf8.encode(
    "--\{key}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\{title}\r\n--\{key}\r\nContent-Disposition: form-data; name=\"html\"; filename=\"conversation.html\"\r\nContent-Type: text/html; charset=utf-8\r\n\r\n\{html}\r\n--\{key}\r\nContent-Disposition: form-data; name=\"json\"; filename=\"conversation.json\"\r\nContent-Type: application/json; charset=utf-8\r\n\r\n\{json}\r\n--\{key}--\r\n",
  )
  guard body.length() <= 20 * 1024 * 1024 else { raise Oversized }
  { key, body, }
}

///|
/// Credentials are supplied by the native login store, never the renderer.
/// Do not follow redirects: the device token belongs only to its issuer.
/// A failed or lost attempt is retried once with the same bytes and key, so
/// no automatic retry creates a second share or uploads a newer snapshot.
pub async fn Snapshot::publish(
  self : Snapshot,
  server_url~ : String,
  token~ : String,
  timeout_ms? : Int = 240_000,
) -> @protocol.SessionShareReply {
  @async.with_timeout(timeout_ms, () => self.send(server_url~, token~)) catch {
    error if @async.is_being_cancelled() => raise error
    _ =>
      @async.with_timeout(timeout_ms, () => self.send(server_url~, token~)) catch {
        error if @async.is_being_cancelled() => raise error
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
) -> @protocol.SessionShareReply {
  let client = @http.Client(server_url)
  defer client.close()
  let response = client.post("/v1/shares", self.body, extra_headers={
    "Authorization": "Bearer \{token}",
    "Idempotency-Key": self.key,
    "Content-Type": "multipart/form-data; boundary=\{self.key}",
  })
  // Bound response memory independently from the (much larger) upload limit.
  let buffer = Buffer()
  while client.read_some(max_len=8192) is Some(bytes) {
    guard buffer.length() + bytes.length() <= 64 * 1024 else {
      return @protocol.Failed(
        message="The share server returned an oversized response.",
      )
    }
    buffer.write_bytes(bytes)
  }
  if response.code == 401 {
    return @protocol.SignInRequired
  }
  let accepted = response.code is (200 | 201)
  // Shown when the body carries no usable JSON. The API answers every
  // rejection with `{ "error": message }`; only a proxy or a deployment
  // without share routes answers without one. Never display an entire
  // HTML/proxy response as an error.
  let fallback = if accepted {
    "The share server did not return a valid share link."
  } else if response.code == 404 {
    "The signed-in server does not provide sharing at \{server_url}/v1/shares (HTTP 404). Sign in to a server with sharing enabled."
  } else {
    "Sharing failed (HTTP \{response.code})."
  }
  let body = @json.parse(@utf8.decode(buffer.to_bytes())) catch {
    _ => return @protocol.Failed(message=fallback)
  }
  match body {
    { "url": String(url), .. } if accepted => @protocol.Shared(url~)
    { "error": String(detail), .. } if !accepted && !detail.trim().is_empty() =>
      @protocol.Failed(
        message="Sharing failed (HTTP \{response.code}): \{detail.trim()}",
      )
    _ => @protocol.Failed(message=fallback)
  }
}
