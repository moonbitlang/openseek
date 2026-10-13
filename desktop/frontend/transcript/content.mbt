///|
/// Display content is independent of model request content: durable images
/// can remain host-owned references until a visible thumbnail requests them.
pub(all) struct Content(Array[ContentPart]) derive(Debug, Eq)

///|
pub(all) enum ContentPart {
  Text(String)
  ImageUrl(url~ : String)
  File(file_id~ : String)
  SessionImage(@desktop_protocol.SessionImageRef)
} derive(Debug, Eq)

///|
pub fn Content::text(self : Content) -> String {
  self.0
  .iter()
  .filter_map(part => {
    match part {
      Text(text) => Some(text)
      _ => None
    }
  })
  .join("")
}

///|
pub fn Content::contains(self : Content, pattern : StringView) -> Bool {
  self.text().contains(pattern)
}

///|
pub fn Content::is_text_only(self : Content) -> Bool {
  self.0.all(part => part is Text(_))
}

///|
pub extend Content with Debug::{to_repr}

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend ContentPart with Debug::{to_repr}

///|
pub extend ContentPart with Eq::{equal, not_equal}
