///|
/// Wraps an ordered array of message parts. Text extraction and structural
/// inspection are separate: extracting text does not imply text-only content.
pub(all) struct Content(Array[ContentPart]) derive(Debug)

///|
pub extend Content with Debug::{to_repr}

///|
/// Concatenates every text part in order, without adding separators. File
/// references contribute no text. Empty and file-only content yield "" because
/// they contain zero text characters; this method does not describe images.
pub fn Content::text(self : Content) -> String {
  self.0
  .iter()
  .filter_map(part => {
    match part {
      Text(text) => Some(text)
      File(_) => None
    }
  })
  .join("")
}

///|
/// Search the concatenated text, including matches spanning text parts.
/// File IDs are excluded, just as in `text()`.
pub fn Content::contains(self : Content, pattern : StringView) -> Bool {
  self.text().contains(pattern)
}

///|
/// Whether every part is text. Empty content is text-only. Use this alongside
/// `text()` when a comparison must not discard file references.
pub fn Content::is_text_only(self : Content) -> Bool {
  self.0.all(part => part is Text(_))
}

///|
/// Visits all text and file parts in their original order.
pub fn Content::iter(self : Content) -> Iter[ContentPart] {
  self.0.iter()
}

///|
/// Supported Chat Completions content parts. `File` encodes directly as
/// {"type":"file","file_id":...}; IDs must belong to the sending API key.
/// Text and file parts retain their order, including interleaved text.
/// `ChatMessage.content` wraps an array of these parts. The encoder
/// handles the API's string alternative; callers do not choose a wire shape.
/// This package currently exposes uploaded-file references; the API's URL and
/// inline file-data alternatives are not yet represented here.
pub(all) enum ContentPart {
  Text(String)
  File(file_id~ : String)
} derive(Debug, Eq)

///|
pub extend ContentPart with Debug::{to_repr}

///|
pub extend ContentPart with Eq::{equal, not_equal}

///|
/// Invalid request content, rejected by request encoders before network IO.
pub(all) suberror ChatMessageError {
  FileContentNotAllowed(Role)
  EmptyFileId
} derive(Debug)

///|
pub extend ChatMessageError with Debug::{to_repr}

///|
impl Show for ChatMessageError with fn output(self, logger) {
  match self {
    FileContentNotAllowed(role) =>
      logger.write_string(
        "file content requires a user or tool message, got \{role}",
      )
    EmptyFileId =>
      logger.write_string("file content part requires a nonblank file_id")
  }
}

///|
fn ChatMessage::validate_content(
  self : ChatMessage,
) -> Unit raise ChatMessageError {
  for part in self.content {
    if part is File(file_id~) {
      match self.role {
        User | Tool(_) => ()
        System | Assistant => raise FileContentNotAllowed(self.role)
      }
      if file_id.is_blank() {
        raise EmptyFileId
      }
    }
  }
}

///|
impl ToJson for ContentPart with fn to_json(self) {
  match self {
    Text(text) => { "type": "text", "text": Json(text) }
    File(file_id~) => { "type": "file", "file_id": Json(file_id) }
  }
}
