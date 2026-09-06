// Address handling: the small, purely lexical slice of URL parsing the
// browser tabs need — enough to normalize what the user typed, name a page
// by its host, and route web links into the dock. Pages themselves are
// navigated by the native view, which does the real parsing.

///|
fn ascii_lower(text : String) -> String {
  let buf = StringBuilder()
  for ch in text {
    buf.write_char(ch.to_ascii_lowercase())
  }
  buf.to_string()
}

///|
/// The authority part of an http(s) URL: everything between `scheme://` and
/// the first `/`, `?`, or `#`. `None` for any other scheme.
fn authority_of(url : String) -> String? {
  let lower = ascii_lower(url)
  let offset = if lower.has_prefix("http://") {
    "http://".length()
  } else if lower.has_prefix("https://") {
    "https://".length()
  } else {
    return None
  }
  Some(head_of(url.view(start_offset=offset)))
}

///|
/// The lowercased host of an http(s) URL: the authority minus any userinfo
/// and port. An IPv6 literal keeps its brackets (`[::1]`).
pub fn host_of(url : String) -> String? {
  guard authority_of(url) is Some(authority) else { return None }
  let host_port = match authority.split("@").collect() {
    [.., after] => after.to_owned()
    [] => authority
  }
  if host_port.has_prefix("[") {
    // An IPv6 literal's colons are not a port separator.
    let buf = StringBuilder()
    for ch in host_port {
      buf.write_char(ch)
      if ch == ']' {
        break
      }
    }
    return Some(ascii_lower(buf.to_string()))
  }
  match host_port.split(":").collect() {
    [host, ..] => Some(ascii_lower(host.to_owned()))
    [] => Some(ascii_lower(host_port))
  }
}

///|
/// Whether the URL is a web page — the only thing a Browser tab's native
/// view can host. Anything else (mailto:, file:, vscode:, …) belongs to the
/// system's own handler. A bare scheme (`http://`) is not a page: the host
/// rejects hostless URLs, and rejecting them here keeps the page state from
/// committing a URL no view will ever load.
pub fn is_web_url(url : String) -> Bool {
  host_of(url) is Some(host) && !host.is_empty()
}

///|
/// The document a URL names: everything before its `#fragment`. Two URLs
/// sharing a document differ only in the anchor a same-document jump
/// scrolls to, which never reloads the page.
fn document_of(url : String) -> String {
  match url.before("#") {
    Some(document) => document.to_owned()
    None => url
  }
}

///|
/// One decimal IPv4 octet's value, or `None` when the text is not one.
fn octet_value(text : StringView) -> Int? {
  guard all_digits(text) && text.length() <= 3 else { return None }
  let value = for ch in text; value = 0 {
    continue value * 10 + (ch.to_int() - '0'.to_int())
  } nobreak {
    value
  }
  if value <= 255 {
    Some(value)
  } else {
    None
  }
}

///|
/// Whether the host is a dotted-quad address in 127/8. Matching the `127.`
/// prefix textually would be wrong: `127.example.com` and `127.com` are
/// ordinary DNS names that resolve to whatever their owner points them at,
/// and calling them loopback would send them plaintext.
fn is_loopback_ipv4(host : String) -> Bool {
  match host.split(".").collect() {
    [first, second, third, fourth] =>
      octet_value(first) == Some(127) &&
      octet_value(second) is Some(_) &&
      octet_value(third) is Some(_) &&
      octet_value(fourth) is Some(_)
    _ => false
  }
}

///|
/// Whether an http(s) URL points at this machine — these force the plain
/// `http://` scheme when the address bar completes a bare host.
pub fn is_loopback(url : String) -> Bool {
  match host_of(url) {
    Some("localhost") | Some("[::1]") => true
    Some(host) => is_loopback_ipv4(host)
    None => false
  }
}

///|
/// Whether the text is one or more digits — the shape that distinguishes a
/// `localhost:5173` port from a `mailto:someone` scheme.
fn all_digits(text : StringView) -> Bool {
  !text.is_empty() && text.all(ch => ch.is_ascii_digit())
}

///|
/// The draft's first segment — everything before the path, query, or
/// fragment — where a scheme or port would live.
fn head_of(text : StringView) -> String {
  let buf = StringBuilder()
  for ch in text {
    if ch == '/' || ch == '?' || ch == '#' {
      break
    }
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
/// What the address bar's draft navigates to: an explicit http(s) URL as
/// typed; a bare host (with an optional `:port` and path) gets a scheme
/// prefixed — `http://` for loopback hosts, `https://` otherwise. Anything
/// else (other schemes, spaces, empty, a hostless URL) is not navigable —
/// the result must pass `is_web_url`, so a committed draft is always one
/// the host will accept.
pub fn normalize_url(input : String) -> String? {
  let trimmed = input.trim().to_owned()
  if trimmed.is_empty() {
    return None
  }
  if trimmed.contains_any(chars=" \t") {
    return None
  }
  let lower = ascii_lower(trimmed)
  let candidate = if lower.has_prefix("http://") || lower.has_prefix("https://") {
    trimmed
  } else {
    // A colon before any slash is either a port (digits) or a foreign scheme.
    match head_of(trimmed.view()).split(":").collect() {
      [_] => ()
      [_, port] if all_digits(port) => ()
      _ => return None
    }
    let candidate = "http://" + trimmed
    if is_loopback(candidate) {
      candidate
    } else {
      "https://" + trimmed
    }
  }
  if is_web_url(candidate) {
    Some(candidate)
  } else {
    None
  }
}
