///|
/// Only public OpenSeek share paths are fetched, without account credentials or
/// redirects. A pasted link cannot select another endpoint on the host.
pub fn share_json_url(input : String) -> String raise {
  let input = input.trim().to_owned()
  guard input.split_once("://") is Some((scheme, rest)) &&
    (scheme == "https" || scheme == "http") &&
    rest.split_once("/") is Some((authority, path)) &&
    !authority.is_empty() &&
    authority
    .iter()
    .all(c => {
      c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9') ||
      c == '.' ||
      c == '-' ||
      c == ':' ||
      c == '[' ||
      c == ']'
    }) else {
    raise SessionImportError("Enter an HTTP or HTTPS OpenSeek share link.")
  }
  let path = path
    .split("?")
    .next()
    .unwrap_or("")
    .split("#")
    .next()
    .unwrap_or("")
    .trim_end(chars="/")
  let parts = path.split("/").to_array()
  guard parts.length() >= 3 &&
    parts[0] == "v1" &&
    parts[1] == "shares" &&
    parts[2].has_prefix("sh_") &&
    parts[2].length() > 3 &&
    parts[2]
    .iter()
    .all(c => {
      c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9') || c == '_' || c == '-'
    }) &&
    (
      parts.length() == 3 ||
      (parts.length() == 4 && parts[3] == "preview") ||
      (parts.length() == 5 && parts[3] == "files" && parts[4] == "json")
    ) else {
    raise SessionImportError("Expected an OpenSeek /v1/shares/sh_… link.")
  }
  "\{scheme}://\{authority}/v1/shares/\{parts[2]}/files/json"
}

///|
async fn download(input : String) -> String {
  let url = share_json_url(input)
  @async.with_timeout(60_000, () => {
    let (response, client) = @http.get_stream(url)
    defer client.close()
    match response.code {
      200 => ()
      404 =>
        raise SessionImportError(
          "The share does not exist or has no JSON file.",
        )
      410 => raise SessionImportError("The share has expired or was revoked.")
      code =>
        raise SessionImportError("Could not download the share (HTTP \{code}).")
    }
    let bytes = @buffer.Buffer()
    while client.read_some(max_len=65536) is Some(chunk) {
      guard bytes.length() + chunk.length() <= MaxBytes else {
        raise SessionImportError("JSON must be no larger than 16 MiB.")
      }
      bytes.write_bytes(chunk)
    }
    @utf8.decode(bytes.to_bytes())
  })
}
