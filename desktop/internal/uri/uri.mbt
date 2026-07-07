// Percent-encoding for the URIs the desktop speaks: the `file:` URIs handed
// to moon-lsp (host side) and the viewer's `openseek:` model URIs (frontend
// side). Encoding walks a string's UTF-8 bytes so every reserved or
// non-ASCII byte escapes as `%XX`; decoding reverses it byte-accurately and
// tolerates malformed input, because half the URIs come back from other
// programs.

///|
/// Percent-encode `text` as a URI path: RFC 3986 unreserved bytes plus the
/// separators a path needs (`/`, and `:` — a legal pchar, and how Windows
/// drive letters survive) stay literal; every other byte (spaces, `#`, `?`,
/// `%`, non-ASCII) escapes as `%XX` of its UTF-8 encoding.
pub fn encode_path(text : StringView) -> String {
  encode_bytes(text, is_path_byte)
}

///|
/// Percent-encode `text` as a single URI component (a query value, one
/// segment): like `encode_path` but `/` and `:` escape too, so the value
/// cannot introduce URI structure.
pub fn encode_component(text : StringView) -> String {
  encode_bytes(text, is_component_byte)
}

///|
/// Decode percent-escapes into UTF-8 bytes and everything else as-is. A
/// malformed escape (`%` without two hex digits) stays literal rather than
/// failing, and invalid UTF-8 decodes lossily — URIs sent by other programs
/// are best-effort input.
pub fn decode(text : StringView) -> String {
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

///|
/// Build a `file:` URI for an absolute filesystem path: backslashes
/// normalize to `/`, a Windows drive path gains the authority-ending slash
/// (`C:\a` → `file:///C:/a`), and reserved or non-ASCII bytes
/// percent-encode.
pub fn file_uri(absolute_path : String) -> String {
  let path = @pathx.normalize(absolute_path)
  let uri = StringBuilder::new()
  uri.write_string("file://")
  if !path.has_prefix("/") {
    uri.write_char('/')
  }
  uri.write_string(encode_path(path))
  uri.to_string()
}

///|
/// The filesystem path a `file:` URI names: scheme and empty authority
/// stripped, percent-escapes decoded as UTF-8, and the spurious leading
/// slash of a Windows drive path dropped (`/C:/a` → `C:/a`). A non-`file:`
/// string passes through untouched.
pub fn file_uri_path(uri : String) -> String {
  guard uri.strip_prefix("file://") is Some(rest) else { return uri }
  let path = decode(rest)
  if path.view() is ['/', drive, ':', ..] && drive is ('A'..='Z' | 'a'..='z') {
    path.view(start_offset=1).to_owned()
  } else {
    path
  }
}

///|
fn encode_bytes(text : StringView, keep : (Int) -> Bool) -> String {
  let out = StringBuilder::new()
  for byte in @utf8.encode(text) {
    let code = byte.to_int()
    if keep(code) {
      out.write_char(code.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(hex_upper(code >> 4))
      out.write_char(hex_upper(code & 0xF))
    }
  }
  out.to_string()
}

///|
fn is_component_byte(code : Int) -> Bool {
  guard code < 0x80 else { return false }
  code.unsafe_to_char()
  is ('A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '.' | '_' | '~')
}

///|
fn is_path_byte(code : Int) -> Bool {
  is_component_byte(code) ||
  (code < 0x80 && code.unsafe_to_char() is ('/' | ':'))
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
