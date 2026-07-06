// `file:` URIs for moon-lsp. LSP speaks RFC 3986 file URIs; naive
// concatenation breaks on Windows drive paths (`file://C:\...` has the
// drive as its authority) and on any path with a space, `#`, `?`, `%`, or
// non-ASCII segment. Encoding walks the path's UTF-8 bytes so every byte
// outside the URI path charset percent-escapes; decoding reverses it for
// the locations the server sends back.

///|
/// Build a `file:` URI for an absolute path: backslashes normalize to `/`,
/// a Windows drive path gains the authority-ending slash
/// (`C:\a` → `file:///C:/a`), and reserved or non-ASCII bytes
/// percent-encode.
fn file_uri(absolute_path : String) -> String {
  let path = absolute_path.replace_all(old="\\", new="/")
  let uri = StringBuilder::new()
  uri.write_string("file://")
  if !path.has_prefix("/") {
    uri.write_char('/')
  }
  for byte in @utf8.encode(path) {
    let code = byte.to_int()
    if is_uri_path_byte(code) {
      uri.write_char(code.unsafe_to_char())
    } else {
      uri.write_char('%')
      uri.write_char(hex_upper(code >> 4))
      uri.write_char(hex_upper(code & 0xF))
    }
  }
  uri.to_string()
}

///|
/// The filesystem path a `file:` URI names: scheme and empty authority
/// stripped, percent-escapes decoded as UTF-8, and the spurious leading
/// slash of a Windows drive path dropped (`/C:/a` → `C:/a`). A non-`file:`
/// string passes through untouched.
fn file_uri_path(uri : String) -> String {
  guard uri.strip_prefix("file://") is Some(rest) else { return uri }
  let path = percent_decode(rest)
  if path.view() is ['/', drive, ':', ..] && drive is ('A'..='Z' | 'a'..='z') {
    path.view(start_offset=1).to_owned()
  } else {
    path
  }
}

///|
/// Bytes a URI path keeps literal: RFC 3986 unreserved plus the separators
/// a path needs (`/`, and `:` for drive letters — a legal pchar).
fn is_uri_path_byte(code : Int) -> Bool {
  guard code < 0x80 else { return false }
  code.unsafe_to_char()
  is ('A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '.' | '_' | '~' | '/' | ':')
}

///|
fn hex_upper(value : Int) -> Char {
  if value < 10 {
    (value + '0'.to_int()).unsafe_to_char()
  } else {
    (value - 10 + 'A'.to_int()).unsafe_to_char()
  }
}

///|
fn hex_value(ch : Char) -> Int? {
  match ch {
    '0'..='9' => Some(ch.to_int() - '0'.to_int())
    'a'..='f' => Some(ch.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(ch.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// Decode percent-escapes into UTF-8 bytes and the rest as-is; a malformed
/// escape (`%` without two hex digits) stays literal rather than failing —
/// server-sent URIs are best-effort input.
fn percent_decode(text : StringView) -> String {
  let bytes = @buffer.Buffer()
  let chars = text.iter().collect()
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch == '%' &&
      index + 2 < chars.length() &&
      hex_value(chars[index + 1]) is Some(high) &&
      hex_value(chars[index + 2]) is Some(low) {
      bytes.write_byte(((high << 4) | low).to_byte())
      index += 3
    } else {
      // Buffer::write_string would append UTF-16; unescaped characters must
      // enter the byte stream as UTF-8 like everything around them.
      bytes.write_bytes(@utf8.encode(ch.to_string()))
      index += 1
    }
  }
  @utf8.decode_lossy(bytes.contents())
}
