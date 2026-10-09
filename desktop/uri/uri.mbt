// Shared desktop URI helpers. Component encoding delegates to `@percent`;
// local file URLs keep URI parsing separate from host filesystem conversion.

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

///|
/// Encode an absolute URI path as a local file URL. Encode each segment so
/// spaces, Unicode, percent signs and fragment/query characters stay in the filename.
pub fn file_url(path : String) -> String {
  "file://" +
  path
  .split("/")
  .map(segment => encode_component(segment).replace(old="%3A", new=":"))
  .collect()
  .join("/")
}

///|
/// Recognize an explicit, nonempty file URL without imposing a file-type
/// policy. The browser or system opener performs the full URL parsing.
pub fn is_file_url(url : String) -> Bool {
  url.to_lower().strip_prefix("file://") is Some(rest) && !rest.is_empty()
}

///|
/// Decode the slash-rooted URI path of a local file URL. Accept an empty or
/// localhost authority, strip query/fragment syntax before decoding, and reject
/// malformed escapes, invalid UTF-8, NUL and network paths. Escaped # and ?
/// remain filename characters; + is literal. Returns None for unsupported URLs.
/// The result retains URI path spelling (including /C:/ on Windows); callers
/// convert it to their host's filesystem path separately.
pub fn local_file_path(url : String) -> String? {
  guard is_file_url(url) else { return None }
  let rest = url[7:]
  let path = if rest.has_prefix("/") {
    rest.to_owned()
  } else if rest.to_owned().to_lower().has_prefix("localhost/") {
    rest[9:].to_owned()
  } else {
    return None
  }
  let end = path.find_by(ch => ch == '#' || ch == '?').unwrap_or(path.length())
  let decoded = @percent.decode(path[:end]) catch { _ => return None }
  guard decoded.has_prefix("/") &&
    !decoded.has_prefix("//") &&
    !decoded.contains("\u0000") else {
    return None
  }
  Some(decoded)
}
