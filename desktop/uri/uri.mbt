// Percent-encoding for the desktop authentication query values. Encoding
// walks a string's UTF-8 bytes so every reserved or non-ASCII byte escapes as
// `%XX`; decoding reverses it byte-accurately and tolerates malformed input
// returned by the browser callback.

///|
/// Percent-encode `text` as a single URI component. Separators and reserved
/// characters escape so an authentication query value cannot introduce URI
/// structure.
pub fn encode_component(text : StringView) -> String {
  encode_bytes(text, is_component_byte)
}

///|
/// Decode one URI component, retaining the entire input if any escape or
/// escaped UTF-8 sequence is malformed. This matches `decodeURIComponent`
/// with a keep-original catch. A plus stays a plus, and escapes decode once.
///
/// ```mbt check
/// test {
///   assert_eq(@uri.decode_component("a%20b%2520"), "a b%20")
///   assert_eq(@uri.decode_component("a%20b%zz"), "a%20b%zz")
/// }
/// ```
pub fn decode_component(text : StringView) -> String {
  let out = StringBuilder()
  let mut rest = text
  while !rest.is_empty() {
    if rest is ['%', ..] {
      let bytes = @buffer.Buffer()
      while rest is ['%', ..] {
        guard rest is ['%', high, low, .. tail] &&
          hex_value(high) is Some(high) &&
          hex_value(low) is Some(low) else {
          return text.to_owned()
        }
        bytes.write_byte(((high << 4) | low).to_byte())
        rest = tail
      }
      let decoded = @utf8.decode(bytes.contents(), ignore_bom=false) catch {
        _ => return text.to_owned()
      }
      out.write_string(decoded)
    } else if rest is [ch, .. tail] {
      out.write_char(ch)
      rest = tail
    }
  }
  out.to_string()
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
fn encode_bytes(text : StringView, keep : (Int) -> Bool) -> String {
  let out = StringBuilder()
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
