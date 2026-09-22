///|
/// Wraps an ordered array of message parts. Text extraction and structural
/// inspection are separate: extracting text does not imply text-only content.
pub(all) struct Content(Array[ContentPart]) derive(Debug, Eq)

///|
pub extend Content with Debug::{to_repr}

///|
pub extend Content with Eq::{equal, not_equal}

///|
/// Preserve the string format for one text part so older readers can still
/// read plain-text records. Other content retains its ordered array of parts.
pub impl ToJson for Content with fn to_json(self) {
  match self.0 {
    [Text(text)] => Json(text)
    parts => Json(parts)
  }
}

///|
/// Read current content arrays and legacy text-only session records.
pub impl FromJson for Content with fn from_json(json, path) {
  match json {
    String(text) => Content([Text(text)])
    Array(_) => Content(@json.from_json(json, path~))
    _ => raise JsonDecodeError((path, "expected content string or array"))
  }
}

///|
/// Concatenates every text part in order, without adding separators. Images
/// contribute no text. Empty and image-only content yield "" because
/// they contain zero text characters; this method does not describe images.
pub fn Content::text(self : Content) -> String {
  self.0
  .iter()
  .filter_map(part => {
    match part {
      Text(text) => Some(text)
      Image(_) => None
    }
  })
  .join("")
}

///|
/// Search the concatenated text, including matches spanning text parts.
/// Images are excluded, just as in `text()`.
pub fn Content::contains(self : Content, pattern : StringView) -> Bool {
  self.text().contains(pattern)
}

///|
/// Whether every part is text. Empty content is text-only. Use this alongside
/// `text()` when a comparison must not discard images.
pub fn Content::is_text_only(self : Content) -> Bool {
  self.0.all(part => part is Text(_))
}

///|
/// Visits all text and image parts in their original order.
pub fn Content::iter(self : Content) -> Iter[ContentPart] {
  self.0.iter()
}

///|
/// Durable content is independent of provider upload IDs.
pub(all) enum ContentPart {
  Text(String)
  Image(Image)
} derive(Debug, Eq)

///|
impl ToJson for ContentPart with fn to_json(self) {
  match self {
    Text(text) => { "type": "text", "text": text }
    Image(image) =>
      {
        "type": "image",
        "media_type": image.media_type,
        "data": @base64.encode(image.bytes),
      }
  }
}

///|
pub impl FromJson for ContentPart with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected content part object"))
  }
  match fields.get("type") {
    Some(String("text")) =>
      Text(
        @json.from_json(
          fields.get("text").unwrap_or(Json::null()),
          path=path.add_key("text"),
        ),
      )
    Some(String("image")) => {
      let media_type : String = @json.from_json(
        fields.get("media_type").unwrap_or(Json::null()),
        path=path.add_key("media_type"),
      )
      let data : String = @json.from_json(
        fields.get("data").unwrap_or(Json::null()),
        path=path.add_key("data"),
      )
      let image = Image::from_base64(media_type~, data) catch {
        error => raise JsonDecodeError((path, "invalid image: \{error}"))
      }
      Image(image)
    }
    _ =>
      raise JsonDecodeError((path.add_key("type"), "unknown content part type"))
  }
}

///|
pub extend Content with ToJson::{to_json}

///|
pub extend Content with FromJson::{from_json}

///|
pub extend ContentPart with Debug::{to_repr}

///|
pub extend ContentPart with Eq::{equal, not_equal}

///|
pub extend ContentPart with FromJson::{from_json}
