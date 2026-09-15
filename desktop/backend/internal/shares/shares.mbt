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
pub(all) suberror ShareError {
  ShareError(String)
}

///|
/// The API limits the title to 1024 UTF-8 bytes, and a generated title may be
/// the entire first prompt. Bound only this metadata, on a Unicode character
/// boundary so neither CJK text nor emoji is split; the HTML and JSON retain
/// the complete records.
fn bounded_title(title : String) -> String {
  let bounded = StringBuilder()
  let mut size = 0
  for c in title.iter() {
    let code = c.to_int()
    size += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
    if size > 1024 {
      break
    }
    bounded.write_char(c)
  }
  bounded.to_string()
}

///|
/// All fields are UTF-8 multipart bodies, never interpolated into headers.
/// The limit includes framing, matching POST /v1/shares on openseek-api.
pub fn Snapshot::Snapshot(
  title~ : String,
  html~ : String,
  json~ : String,
) -> Snapshot raise ShareError {
  let title = bounded_title(title.trim().to_owned())
  guard !title.is_empty() else {
    raise ShareError("The conversation title must not be empty.")
  }
  guard @entropy.random_hex(32) is Some(key) else {
    raise ShareError(
      "Could not create a secure share request. Please try again.",
    )
  }
  let body = @utf8.encode(
    "--\{key}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n\{title}\r\n--\{key}\r\nContent-Disposition: form-data; name=\"html\"; filename=\"conversation.html\"\r\nContent-Type: text/html; charset=utf-8\r\n\r\n\{html}\r\n--\{key}\r\nContent-Disposition: form-data; name=\"json\"; filename=\"conversation.json\"\r\nContent-Type: application/json; charset=utf-8\r\n\r\n\{json}\r\n--\{key}--\r\n",
  )
  guard body.length() <= 20 * 1024 * 1024 else {
    raise ShareError(
      "This export exceeds the 20 MiB share limit. Use Download instead.",
    )
  }
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
  let mut outcome = self.attempt(server_url~, token~, timeout_ms~)
  if outcome is Err(_) {
    outcome = self.attempt(server_url~, token~, timeout_ms~)
  }
  match outcome {
    Ok(reply) => reply
    Err(message) => @protocol.Failed(message~)
  }
}

///|
async fn Snapshot::attempt(
  self : Snapshot,
  server_url~ : String,
  token~ : String,
  timeout_ms~ : Int,
) -> Result[@protocol.SessionShareReply, String] {
  let reply = @async.with_timeout_opt(timeout_ms, () => {
    self.send(server_url~, token~)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => return Err("The share request failed: \{error}")
  }
  match reply {
    Some(reply) => Ok(reply)
    None => Err("The share request timed out. Please try again.")
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
  let body : Json? = Some(@json.parse(@utf8.decode(buffer.to_bytes()))) catch {
    _ => None
  }
  guard response.code is (200 | 201) else {
    // The API answers every rejection with `{ "error": message }`; only a
    // proxy or a deployment without share routes answers without one. Never
    // display an entire HTML/proxy response as an error.
    let message = match body {
      Some({ "error": String(detail), .. }) if !detail.trim().is_empty() =>
        "Sharing failed (HTTP \{response.code}): \{detail.trim()}"
      _ if response.code == 404 =>
        "The signed-in server does not provide sharing at \{server_url}/v1/shares (HTTP 404). Sign in to a server with sharing enabled."
      _ => "Sharing failed (HTTP \{response.code})."
    }
    return @protocol.Failed(message~)
  }
  match body {
    Some({ "url": String(url), .. }) if url.has_prefix("https://") ||
      url.has_prefix("http://") => @protocol.Shared(url~)
    _ =>
      @protocol.Failed(
        message="The share server did not return a valid share link.",
      )
  }
}
