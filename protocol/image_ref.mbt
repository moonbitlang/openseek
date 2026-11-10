///|
/// Immutable local attachment identity. Provider file IDs are kept separately.
#derive(Eq, Debug)
pub struct ImageRef {
  attachment_id : String
  media_type : String
  bytes : Int32
}

///|
/// Validate an attachment reference without accessing storage.
pub fn ImageRef::ImageRef(
  attachment_id~ : String,
  media_type~ : String,
  bytes~ : Int32,
) -> ImageRef raise {
  guard attachment_id.strip_prefix("sha256:") is Some(digest) &&
    digest.length() == 64 &&
    digest.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    fail("invalid image attachment id")
  }
  guard media_type is ("image/png" | "image/jpeg" | "image/gif" | "image/webp") &&
    bytes > 0 &&
    bytes <= 5 * 1024 * 1024 else {
    fail("invalid image attachment metadata")
  }
  { attachment_id, media_type, bytes, }
}

///|
pub impl ToJson for ImageRef with fn to_json(self) {
  {
    "type": "image",
    "attachment_id": self.attachment_id,
    "media_type": self.media_type,
    "bytes": self.bytes,
  }
}

///|
pub impl FromJson for ImageRef with fn from_json(json, path) {
  guard json
    is {
      "attachment_id": String(attachment_id),
      "media_type": String(media_type),
      "bytes": size,
      ..
    } else {
    raise JsonDecodeError((path, "expected image attachment reference"))
  }
  let bytes : Int32 = @json.from_json(size, path=path.add_key("bytes"))
  ImageRef(attachment_id~, media_type~, bytes~) catch {
    error => raise JsonDecodeError((path, "invalid image attachment: \{error}"))
  }
}

///|
const AttachmentUrlScheme = "openseek-attachment:"

///|
/// Internal image address that lets composer drafts and image lists carry a
/// stored attachment next to data URLs. Never sent to a model provider.
pub fn ImageRef::url(self : ImageRef) -> String {
  "\{AttachmentUrlScheme}\{self.attachment_id}:\{self.media_type}:\{self.bytes}"
}

///|
/// Whether `url` is an internal attachment address rather than an image URL.
pub fn is_attachment_url(url : String) -> Bool {
  url.has_prefix(AttachmentUrlScheme)
}

///|
/// Parse one image list entry: an attachment address becomes a reference and
/// anything else must be a base64 data URL.
pub fn ContentPart::from_image_url(url : String) -> ContentPart raise {
  if is_attachment_url(url) {
    ImageRef(ImageRef::from_url(url))
  } else {
    Image(Image::from_data_url(url))
  }
}

///|
/// Decode an internal attachment address. Invalid addresses are errors.
pub fn ImageRef::from_url(url : String) -> ImageRef raise {
  guard url.split(":").collect()
    is ["openseek-attachment", "sha256", digest, media_type, size] else {
    fail("invalid image attachment URL")
  }
  ImageRef(
    attachment_id="sha256:\{digest}",
    media_type=media_type.to_owned(),
    bytes=@string.parse_int(size),
  )
}

///|
pub extend ImageRef with Eq::{equal, not_equal}

///|
pub extend ImageRef with Debug::{to_repr}

///|
pub extend ImageRef with ToJson::{to_json}

///|
pub extend ImageRef with FromJson::{from_json}
