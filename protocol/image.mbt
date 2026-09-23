///|
/// Immutable image bytes. JSONL stores base64; no path or provider ID is needed
/// to replay the image. Constructors check size and raster signatures, not a
/// full pixel decode. Images are never resized or re-encoded by this module.
pub struct Image {
  media_type : String
  bytes : Bytes
} derive(Eq)

///|
/// Invalid image input, distinguished without retaining the base64 payload.
pub(all) suberror ImageError {
  TooLarge
  InvalidBase64
  UnsupportedFormat
  MediaTypeMismatch(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
impl Show for ImageError with fn output(self, logger) {
  match self {
    TooLarge => logger.write_string("image exceeds the 5 MiB limit")
    InvalidBase64 =>
      logger.write_string("image data must be canonical padded base64")
    UnsupportedFormat =>
      logger.write_string("expected PNG, JPEG, GIF, or WebP image bytes")
    MediaTypeMismatch(expected~, actual~) =>
      logger.write_string(
        "image declares \{expected} but bytes identify \{actual}",
      )
  }
}

///|
/// Limit applies to decoded bytes; base64 input is bounded before allocating.
pub fn Image::from_bytes(bytes : Bytes) -> Image raise ImageError {
  if bytes.length() > 5 * 1024 * 1024 {
    raise TooLarge
  }
  let media_type = match bytes {
    [b'\x89', b'P', b'N', b'G', b'\r', b'\n', b'\x1a', b'\n', ..] => "image/png"
    [b'\xff', b'\xd8', b'\xff', ..] => "image/jpeg"
    [b'G', b'I', b'F', b'8', b'7' | b'9', b'a', ..] => "image/gif"
    [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] =>
      "image/webp"
    _ => raise UnsupportedFormat
  }
  { media_type, bytes, }
}

///|
/// Decode canonical padded base64 and verify the declared MIME against its signature.
pub fn Image::from_base64(
  media_type~ : StringView,
  data : StringView,
) -> Image raise ImageError {
  if data.length() > (5 * 1024 * 1024 + 2) / 3 * 4 {
    raise TooLarge
  }
  let bytes = @base64.decode(data) catch { _ => raise InvalidBase64 }
  if @base64.encode(bytes)[:] != data {
    raise InvalidBase64
  }
  let image = Image::from_bytes(bytes)
  if image.media_type[:] != media_type {
    raise MediaTypeMismatch(
      expected=media_type.to_owned(),
      actual=image.media_type,
    )
  }
  image
}

///|
/// Build an inline URL suitable for local image display.
pub fn Image::data_url(self : Image) -> String {
  "data:\{self.media_type};base64,\{@base64.encode(self.bytes)}"
}

///|
/// Debug output must not expand a whole binary image into logs or snapshots.
pub impl Debug for Image with fn to_repr(self) {
  Repr("Image(\{self.media_type}, \{self.bytes.length()} bytes)")
}

///|
pub extend Image with Eq::{equal, not_equal}

///|
pub extend ImageError with Debug::{to_repr}

///|
pub extend ImageError with Eq::{equal, not_equal}

///|
pub extend Image with Debug::{to_repr}

///|
/// Decode an inline raster image URL, retaining its original file bytes.
pub fn Image::from_data_url(url : String) -> Image raise ImageError {
  guard url.strip_prefix("data:") is Some(value) &&
    value.split_once(";base64,") is Some((media_type, data)) else {
    raise InvalidBase64
  }
  Image::from_base64(media_type~, data)
}
