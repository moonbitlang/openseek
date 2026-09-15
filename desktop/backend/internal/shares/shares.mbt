///|
/// One immutable upload: a retry must retain both the rendered conversation
/// and its idempotency key, even while the live conversation changes.
struct Snapshot {
  key : String
  boundary : String
  body : Bytes
}

///|
pub(all) suberror ShareError {
  ShareError(String)
}

///|
priv struct ServerError {
  message : String
}

///|
/// The API returns a required nonempty error string. Ignore unrelated fields;
/// missing, null, or malformed errors use the HTTP status fallback instead.
impl @json.FromJson for ServerError with fn from_json(json, path) {
  guard json is { "error": String(message), .. } && !message.trim().is_empty() else {
    raise @json.JsonDecodeError((path, "expected a nonempty share error"))
  }
  { message: message.trim().to_owned(), }
}

///|
// Production only receives this wire type; keep its explicit encoder for
// the protocol round-trip test, as with other desktop JSON types.
#warnings("-unused_value")
impl ToJson for ServerError with fn to_json(self) {
  { "error": self.message }
}

///|
/// Keep diagnostics readable even if a proxy returns a very long JSON error.
/// Iterating characters avoids splitting a Unicode character at the limit.
fn ServerError::describe(self : ServerError, code : Int) -> String {
  let detail = StringBuilder()
  for c in self.message.iter().take(2048) {
    detail.write_char(c)
  }
  let text = detail.to_string()
  let suffix = if text.length() < self.message.length() { "…" } else { "" }
  "Sharing failed (HTTP \{code}): \{text}\{suffix}"
}

///|
/// All fields are UTF-8 multipart bodies, never interpolated into headers.
/// The limit includes framing, matching POST /v1/shares on openseek-api.
pub fn Snapshot::Snapshot(
  title~ : String,
  html~ : String,
  json~ : String,
) -> Snapshot raise ShareError {
  let title_size = @utf8.encode(title).length()
  guard title_size > 0 && title_size <= 1024 && !title.trim().is_empty() else {
    raise ShareError("The conversation title must be between 1 and 1024 bytes.")
  }
  guard @entropy.random_hex(32) is Some(key) else {
    raise ShareError(
      "Could not create a secure share request. Please try again.",
    )
  }
  // RFC 7578 section 4 uses RFC 2046 section 5.1.1 multipart syntax: boundary
  // values contain 1–70 characters, excluding delimiter hyphens and CRLF.
  // https://www.rfc-editor.org/rfc/rfc2046#section-5.1.1
  // The hex key is 64 characters; the former "openseek_" prefix exceeded 70.
  let boundary = key
  guard !title.contains(boundary) &&
    !html.contains(boundary) &&
    !json.contains(boundary) else {
    raise ShareError("Could not encode the share request. Please try again.")
  }
  let body = @utf8.encode(
    "--\{boundary}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\{title}\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"html\"; filename=\"conversation.html\"\r\nContent-Type: text/html; charset=utf-8\r\n\r\n\{html}\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"json\"; filename=\"conversation.json\"\r\nContent-Type: application/json; charset=utf-8\r\n\r\n\{json}\r\n--\{boundary}--\r\n",
  )
  guard body.length() <= 20 * 1024 * 1024 else {
    raise ShareError(
      "This export exceeds the 20 MiB share limit. Use Download instead.",
    )
  }
  { key, boundary, body, }
}

///|
/// Credentials are supplied by the native login store, never the renderer.
/// Do not follow redirects: the device token belongs only to its issuer.
/// A lost response is retried once with the same bytes and key. No automatic
/// retry creates a second share or uploads a newer conversation snapshot.
pub async fn Snapshot::publish(
  self : Snapshot,
  server_url~ : String,
  token~ : String,
) -> @protocol.SessionShareReply {
  for attempt = 0; attempt < 2; attempt = attempt + 1 {
    let result = @async.with_timeout_opt(240_000, () => {
      self.send(server_url~, token~)
    }) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    if result is Some(reply) {
      return reply
    }
  }
  @protocol.Failed(
    message="Could not confirm publication. Check your connection; a share may already have been created. Sharing again starts a new upload.",
  )
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
    "Content-Type": "multipart/form-data; boundary=\{self.boundary}",
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
  guard response.code is (200 | 201) else {
    // Preserve the API's explanation rather than reducing every rejection to
    // its status code. Never display an entire HTML/proxy response as an error.
    let detail : ServerError? = Some(
      @json.from_json(@json.parse(@utf8.decode(buffer.to_bytes()))),
    ) catch {
      _ => None
    }
    if detail is Some(error) {
      return @protocol.Failed(message=error.describe(response.code))
    }
    let message = match response.code {
      // A device login can still point at a deployment without share routes.
      // Name the requested server so this cannot be mistaken for a missing
      // local conversation or an object-storage upload failure.
      404 =>
        "The signed-in server does not provide sharing at \{server_url}/v1/shares (HTTP 404). Sign in to a server with sharing enabled."
      413 => "This export exceeds the 20 MiB share limit. Use Download instead."
      429 => "The share limit has been reached. Please try again later."
      502 | 503 =>
        "Sharing is unavailable on this server. Please try again later."
      409 =>
        "The server is still processing this share. Please wait before trying again."
      _ => "Sharing failed (HTTP \{response.code})."
    }
    return @protocol.Failed(message~)
  }
  let decoded = @json.parse(@utf8.decode(buffer.to_bytes())) catch {
    _ =>
      return @protocol.Failed(
        message="The share server returned an invalid response.",
      )
  }
  match decoded {
    { "url": String(url), "expires_at": String(expires_at), .. } if (
        url.has_prefix("https://") || url.has_prefix("http://")
      ) &&
      !expires_at.is_empty() => @protocol.Shared(url~, expires_at~)
    _ =>
      @protocol.Failed(
        message="The share server did not return a link and expiry.",
      )
  }
}
