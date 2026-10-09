// File-content classification shared by the built-in viewer and host replies.
// This is deliberately not general MIME detection: it recognizes only the
// supported raster formats and PDFs, then applies the viewer's UTF-8 text
// policy to everything else.

///|
/// What the desktop can do with one bounded file payload. `Utf8Text` includes
/// the decoded content so consumers do not validate and decode the same bytes
/// in separate passes.
pub enum Classification {
  Utf8Text(String)
  Image(media_type~ : String)
  Pdf
  UnknownBinary
} derive(Debug, Eq)

///|
/// Classify bytes according to the desktop viewer's content contract.
/// Supported raster signatures take precedence because their payloads commonly
/// contain NUL bytes. Other content is text only when it is neither a PDF nor
/// NUL-containing and decodes as strict UTF-8.
pub fn classify(bytes : BytesView) -> Classification {
  match bytes {
    [b'\x89', b'P', b'N', b'G', b'\r', b'\n', b'\x1a', b'\n', ..] =>
      Image(media_type="image/png")
    [b'\xff', b'\xd8', b'\xff', ..] => Image(media_type="image/jpeg")
    [b'G', b'I', b'F', b'8', b'7', b'a', ..]
    | [b'G', b'I', b'F', b'8', b'9', b'a', ..] => Image(media_type="image/gif")
    [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] =>
      Image(media_type="image/webp")
    [b'%', b'P', b'D', b'F', b'-', ..] => Pdf
    _ if bytes.find(b"\x00") is Some(_) => UnknownBinary
    _ => {
      let text = @utf8.decode(bytes) catch { _ => return UnknownBinary }
      Utf8Text(text)
    }
  }
}

///|
pub extend Classification with Debug::{to_repr}

///|
pub extend Classification with Eq::{equal, not_equal}
