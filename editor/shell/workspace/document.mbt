///|
/// Provider-owned immutable document content for one URI/revision.
pub struct DocumentSnapshot {
  uri : @base_common.Uri
  display_name : String
  language_id : String
  revision : String
  text : String
  priv line_starts : Array[Int]
} derive(Debug)

///|
/// Provider read result without exceptions.
pub(all) enum DocumentReadResult {
  DocumentLoaded(DocumentSnapshot)
  DocumentNotFound(@base_common.Uri)
  DocumentReadFailed(DocumentError)
} derive(Debug)

///|
/// Push notification from a provider watch or host-owned watcher.
pub(all) enum DocumentChange {
  DocumentInvalidated(uri~ : @base_common.Uri, known_revision~ : String?)
  DocumentUpdated(DocumentSnapshot)
  DocumentDeleted(@base_common.Uri)
  DocumentChangeFailed(uri~ : @base_common.Uri, error~ : DocumentError)
} derive(Debug)

///|
/// Document source contract for the readonly viewer. Providers may coalesce
/// watch updates and can either invalidate a URI or provide a fresh snapshot.
pub(open) trait DocumentProvider {
  async fn read(Self, @base_common.Uri) -> DocumentReadResult
  fn watch(Self, @base_common.Uri, (DocumentChange) -> Unit) -> @base_common.Disposable
  fn close(Self, @base_common.Uri) -> Unit
}

///|
/// Builds a document error, defaulting an empty message to the code label.
pub fn DocumentError::DocumentError(
  code : FileSystemProviderErrorCode,
  message : String,
  uri? : @base_common.Uri,
) -> DocumentError {
  let message = if message == "" { code.to_string() } else { message }
  { code, message, uri, }
}

///|
/// Converts a lower-level filesystem provider failure into a document error.
fn DocumentError::from_file_system_error(
  error : FileSystemProviderError,
) -> DocumentError {
  { code: error.code, message: error.message, uri: error.uri, }
}

///|
/// Builds an immutable raw provider snapshot. EOL bytes/code units are kept
/// exactly as supplied; normalization begins only when a Viewer `TextModel`
/// constructs its `TextSnapshot`.
pub fn DocumentSnapshot::DocumentSnapshot(
  uri : @base_common.Uri,
  display_name : String,
  language_id : String,
  revision : String,
  text : String,
) -> DocumentSnapshot {
  let display_name = if display_name == "" {
    @base_common.basename_or_authority(uri)
  } else {
    display_name
  }
  let language_id = if language_id == "" {
    infer_language_id(display_name)
  } else {
    language_id
  }
  let revision = if revision == "" {
    revision_from_text(text)
  } else {
    revision
  }
  {
    uri,
    display_name,
    language_id,
    revision,
    text,
    line_starts: build_line_starts(text),
  }
}

///|
/// Snapshot length in the repo's JavaScript-compatible UTF-16 indexing model.
fn DocumentSnapshot::length_impl(self : DocumentSnapshot) -> Int {
  self.text.length()
}

///|
/// Number of logical lines, including the final empty line after a trailing
/// newline.
fn DocumentSnapshot::line_count_impl(self : DocumentSnapshot) -> Int {
  self.line_starts.length()
}

///|
/// Start offset for `line`, clamped into the snapshot's line range.
fn DocumentSnapshot::line_start_offset_impl(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  let line = line.clamp(min=0, max=self.line_count() - 1)
  self.line_starts[line]
}

///|
/// End offset for `line`, clamped into the snapshot's line range and excluding
/// the line break. CRLF lines exclude both the `\r` and `\n`.
fn DocumentSnapshot::line_end_offset_impl(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  let line = line.clamp(min=0, max=self.line_count() - 1)
  let raw_end = if line + 1 < self.line_count() {
    self.line_starts[line + 1] - 1
  } else {
    self.length()
  }
  if raw_end > self.line_starts[line] && self.text[raw_end - 1].to_int() == 13 {
    raw_end - 1
  } else {
    raw_end
  }
}

///|
/// Returns a clamped half-open slice of the snapshot text.
fn DocumentSnapshot::slice_impl(
  self : DocumentSnapshot,
  range : @base_common.OffsetRange,
) -> String {
  let start = range.start.clamp(min=0, max=self.length())
  let end = range.end_exclusive.clamp(min=start, max=self.length())
  self.text[start:end].to_owned()
}

///|
/// Zero-based line containing `offset`, with out-of-range offsets clamped to
/// the snapshot.
fn DocumentSnapshot::line_at_offset_impl(
  self : DocumentSnapshot,
  offset : Int,
) -> Int {
  let offset = offset.clamp(min=0, max=self.length())
  for i in 0..<self.line_starts.length(); found = 0 {
    continue if self.line_starts[i] <= offset { i } else { found }
  } nobreak {
    found
  }
}

///|
/// Converts an offset to a one-based line/column `Position` (Monaco's
/// convention; the offset↔position boundary adds +1 on both axes).
fn DocumentSnapshot::position_at_offset_impl(
  self : DocumentSnapshot,
  offset : Int,
) -> @base_common.Position {
  let offset = offset.clamp(min=0, max=self.length())
  let line = self.line_at_offset(offset)
  { line_number: line + 1, column: offset - self.line_starts[line] + 1, }
}

///|
/// Converts a one-based line/column `Position` to a clamped document offset,
/// undoing the +1 this boundary added in `position_at_offset`.
fn DocumentSnapshot::offset_at_position_impl(
  self : DocumentSnapshot,
  position : @base_common.Position,
) -> Int {
  let line = (position.line_number - 1).clamp(min=0, max=self.line_count() - 1)
  let start = self.line_start_offset(line)
  let end = self.line_end_offset(line)
  (start + position.column - 1).clamp(min=start, max=end)
}

///|
/// JSON shape emitted to browser harnesses and remote protocol adapters.
pub impl ToJson for DocumentSnapshot with fn to_json(self) {
  {
    "uri": self.uri.to_string().to_json(),
    "displayName": self.display_name.to_json(),
    "languageId": self.language_id.to_json(),
    "revision": self.revision.to_json(),
    "text": self.text.to_json(),
  }
}

///|
/// JSON shape for document errors.
pub impl ToJson for DocumentError with fn to_json(self) {
  ToJson::to_json(self.to_file_system_error())
}

///|
/// Offsets where each line begins in the raw provider text (0-based). Mirrors
/// Monaco's raw `createLineStartsFast` scan (`pieceTreeBase.ts:37`): `\n`, a
/// lonely `\r`, and `\r\n` each end a line, with the pair counted once. This
/// scanner intentionally differs from Viewer `TextSnapshot`, which first
/// normalizes CRLF/CR to LF and then derives its own coordinate table.
fn build_line_starts(text : String) -> Array[Int] {
  let starts = [0]
  let len = text.length()
  let mut i = 0
  while i < len {
    let code = text[i].to_int()
    if code == 13 {
      if i + 1 < len && text[i + 1].to_int() == 10 {
        // \r\n... case
        starts.push(i + 2)
        i += 2
      } else {
        // \r... case
        starts.push(i + 1)
        i += 1
      }
    } else {
      if code == 10 {
        starts.push(i + 1)
      }
      i += 1
    }
  }
  starts
}

///|
pub extend DocumentChange with Debug::{to_repr}

///|
pub extend DocumentError with ToJson::{to_json}

///|
pub extend DocumentReadResult with Debug::{to_repr}

///|
pub extend DocumentSnapshot with Debug::{to_repr}

///|
pub extend DocumentSnapshot with ToJson::{to_json}
