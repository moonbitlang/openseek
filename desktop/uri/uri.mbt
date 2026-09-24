// Percent-encoding for the desktop authentication query values, delegating to
// `@percent`. Decoding tolerates malformed input returned by the browser
// callback.

///|
/// Percent-encode `text` as a single URI component. Separators and reserved
/// characters escape so an authentication query value cannot introduce URI
/// structure.
pub fn encode_component(text : StringView) -> String {
  @percent.encode(text)
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
  @percent.decode(text) catch {
    Malformed(_) => text.to_owned()
  }
}

///|
/// Decode percent-escapes into UTF-8 bytes and everything else as-is. A
/// malformed escape (`%` without two hex digits) stays literal rather than
/// failing, and invalid UTF-8 decodes lossily — URIs sent by other programs
/// are best-effort input.
pub fn decode(text : StringView) -> String {
  @percent.decode_lossy(text)
}
