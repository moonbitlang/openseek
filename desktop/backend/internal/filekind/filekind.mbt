// File-content classification shared by the built-in viewer and host replies.
// This is deliberately not general MIME detection: it recognizes only the
// raster formats the transcript can render, then applies the viewer's UTF-8
// text policy to everything else.

///|
/// What the desktop can do with one bounded file payload. `Utf8Text` includes
/// the decoded content so consumers do not validate and decode the same bytes
/// in separate passes.
pub enum Classification {
  Utf8Text(String)
  RasterImage(media_type~ : String)
  Binary
} derive(Debug, Eq)

///|
/// Classify bytes according to the desktop viewer's content contract.
/// Supported raster signatures take precedence because their payloads commonly
/// contain NUL bytes. Other content is text only when it is neither a PDF nor
/// NUL-containing and decodes as strict UTF-8.
pub fn classify(bytes : BytesView) -> Classification {
  match bytes {
    [b'\x89', b'P', b'N', b'G', b'\r', b'\n', b'\x1a', b'\n', ..] =>
      RasterImage(media_type="image/png")
    [b'\xff', b'\xd8', b'\xff', ..] => RasterImage(media_type="image/jpeg")
    [b'G', b'I', b'F', b'8', b'7', b'a', ..]
    | [b'G', b'I', b'F', b'8', b'9', b'a', ..] =>
      RasterImage(media_type="image/gif")
    [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] =>
      RasterImage(media_type="image/webp")
    [b'%', b'P', b'D', b'F', b'-', ..] => Binary
    _ if bytes.find(b"\x00") is Some(_) => Binary
    _ => {
      let text = @utf8.decode(bytes) catch { _ => return Binary }
      Utf8Text(text)
    }
  }
}

///|
pub extend Classification with Debug::{to_repr}

///|
pub extend Classification with Eq::{equal, not_equal}
