///|
/// Root-relative source path accepted from UI or protocol input after
/// normalization rejects absolute paths, parent traversal, and NUL bytes.
struct SourcePath {
  value : String
} derive(Eq, Debug)

///|
/// Validation failures for user-facing source paths and document URIs.
pub(all) enum SourceError {
  MissingPath
  InvalidPath
} derive(Eq, Debug)

///|
/// Result wrapper used instead of raising while normalizing source paths.
pub enum SourcePathResult {
  ParsedSourcePath(SourcePath)
  SourcePathError(SourceError)
} derive(Eq, Debug)

///|
/// Raw file text plus metadata needed to construct a `DocumentSnapshot`.
struct DocumentContent {
  text : String
  display_name : String
  language_id : String
  revision : String
} derive(Debug)

///|
/// Builds file content while allowing providers to omit derived metadata.
pub fn DocumentContent::DocumentContent(
  text : String,
  display_name? : String = "",
  language_id? : String = "",
  revision? : String = "",
) -> DocumentContent {
  { text, display_name, language_id, revision, }
}

///|
/// Stable protocol/debug label for source validation failures.
pub fn SourceError::to_string(self : SourceError) -> String {
  match self {
    MissingPath => "MissingPath"
    InvalidPath => "InvalidPath"
  }
}

///|
/// Normalizes a user-provided workspace path into a safe root-relative path.
pub fn SourcePath::normalize_root_relative_path(
  raw_path : String,
) -> SourcePathResult {
  if raw_path == "" {
    return SourcePathError(MissingPath)
  }
  if contains_null(raw_path) {
    return SourcePathError(InvalidPath)
  }
  let slash_path = raw_path.replace_all(old="\\", new="/")
  if slash_path.has_prefix("/") ||
    slash_path.has_prefix("//") ||
    is_windows_drive_path(slash_path) {
    return SourcePathError(InvalidPath)
  }

  let segments = []
  for segment_view in slash_path.split("/") {
    let segment = segment_view.to_owned()
    if segment == ".." {
      return SourcePathError(InvalidPath)
    }
    if segment != "" && segment != "." {
      segments.push(segment)
    }
  }
  guard segments is [_, ..] else { return SourcePathError(InvalidPath) }
  ParsedSourcePath({ value: segments.join("/"), })
}

///|
/// Returns the normalized root-relative path string.
pub fn SourcePath::to_string(self : SourcePath) -> String {
  self.value
}

///|
/// Display label for a source path; currently the normalized path itself.
pub fn SourcePath::display_name(self : SourcePath) -> String {
  self.value
}

///|
/// Text of one logical line without its line break.
pub fn DocumentSnapshot::line_text(
  self : DocumentSnapshot,
  line : Int,
) -> String {
  let start = self.line_start_offset(line)
  let end = self.line_end_offset(line)
  self.text[start:end].to_owned()
}

///|
/// Host-neutral error codes used by file providers and remote workspace
/// responses.
pub(all) enum FileSystemProviderErrorCode {
  FileNotFound
  FileExists
  FileNotADirectory
  IsDirectory
  NoPermissions
  Unavailable
  InvalidUri
  InvalidData
} derive(Eq, Debug)

///|
/// File-provider failure with optional URI context.
pub struct FileSystemProviderError {
  code : FileSystemProviderErrorCode
  message : String
  uri : @base_common.Uri?
} derive(Debug)

///|
/// Document-level failure with optional URI context.
pub struct DocumentError {
  code : FileSystemProviderErrorCode
  message : String
  uri : @base_common.Uri?
} derive(Debug)

///|
/// Provider read result without exceptions, so browser and native providers can
/// share the same contract.
pub(all) enum FileReadResult {
  FileReadOk(DocumentContent)
  FileReadError(FileSystemProviderError)
} derive(Debug)

///|
/// File-watch event kind. Providers may coalesce events before delivering
/// them.
pub(all) enum FileChangeType {
  Created
  Changed
  Deleted
} derive(Eq, Debug)

///|
/// One changed document URI reported by a file watch.
pub(all) struct FileChange {
  uri : @base_common.Uri
  change_type : FileChangeType
} derive(Debug)

///|
/// Watch behavior requested from a provider.
pub struct WatchOptions {
  recursive : Bool
  excludes : Array[String]
} derive(Debug)

///|
/// Disposable watch handle. Calling `dispose` must stop future callbacks for
/// that watch when the provider can do so.
pub(all) struct FileWatch {
  dispose : () -> Unit
}

///|
/// Host filesystem abstraction for readonly document loading and file-change
/// notifications.
pub(open) trait FileSystemProvider {
  fn scheme(Self) -> String
  async fn read_file(Self, @base_common.Uri) -> FileReadResult
  fn watch(Self, @base_common.Uri, WatchOptions, (Array[FileChange]) -> Unit) -> FileWatch
}

///|
/// Default non-recursive watch with no excludes.
pub fn WatchOptions::default() -> WatchOptions {
  { recursive: false, excludes: [], }
}

///|
/// Stops the watch through the provider-supplied disposer.
pub fn FileWatch::dispose(self : FileWatch) -> Unit {
  (self.dispose)()
}

///|
/// Converts a document error back to the lower-level error shape when protocol
/// adapters need the existing provider-code JSON format.
pub fn DocumentError::to_file_system_error(
  self : DocumentError,
) -> FileSystemProviderError {
  { code: self.code, message: self.message, uri: self.uri, }
}

///|
/// Derives a snapshot from provider content, filling display name, language id,
/// and revision when they are absent.
pub fn DocumentSnapshot::from_content(
  uri : @base_common.Uri,
  content : DocumentContent,
) -> DocumentSnapshot {
  DocumentSnapshot(
    uri,
    content.display_name,
    content.language_id,
    content.revision,
    content.text,
  )
}

///|
/// JSON shape for document read results.
pub impl ToJson for DocumentReadResult with fn to_json(self) {
  match self {
    DocumentLoaded(document) =>
      { "ok": true, "document": ToJson::to_json(document) }
    DocumentNotFound(uri) =>
      { "ok": false, "notFound": true, "uri": uri.to_string().to_json() }
    DocumentReadFailed(error) =>
      { "ok": false, "error": ToJson::to_json(error) }
  }
}

///|
/// JSON shape for provider errors, including HTTP-like status for the native
/// reference server.
pub impl ToJson for FileSystemProviderError with fn to_json(self) {
  let fields : Map[String, Json] = {
    "code": self.code.to_string().to_json(),
    "message": self.message.to_json(),
    "status": self.status().to_json(),
  }
  if self.uri is Some(uri) {
    fields["uri"] = uri.to_string().to_json()
    fields["displayName"] = @base_common.basename_or_authority(uri).to_json()
  }
  Json(fields)
}

///|
/// JSON shape for watch events.
pub impl ToJson for FileChange with fn to_json(self) {
  {
    "uri": self.uri.to_string().to_json(),
    "type": self.change_type.to_string().to_json(),
  }
}

///|
/// Document-provider adapters retained as the documented host-neutral
/// workspace contract.
pub async fn read_document(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
) -> DocumentReadResult {
  read_document_impl(provider, uri)
}

///|
pub fn watch_file(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
  listener : (Array[FileChange]) -> Unit,
) -> FileWatch {
  watch_file_impl(provider, uri, listener)
}

///|
/// Stable content-derived revision retained for provider implementations.
pub fn revision_from_text(text : String) -> String {
  revision_from_text_impl(text)
}

///|
/// Snapshot length in the repo's JavaScript-compatible UTF-16 indexing model.
pub fn DocumentSnapshot::length(self : DocumentSnapshot) -> Int {
  self.length_impl()
}

///|
/// Number of logical lines, including a final empty line after a newline.
pub fn DocumentSnapshot::line_count(self : DocumentSnapshot) -> Int {
  self.line_count_impl()
}

///|
pub fn DocumentSnapshot::line_start_offset(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  self.line_start_offset_impl(line)
}

///|
pub fn DocumentSnapshot::line_end_offset(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  self.line_end_offset_impl(line)
}

///|
pub fn DocumentSnapshot::slice(
  self : DocumentSnapshot,
  range : @base_common.OffsetRange,
) -> String {
  self.slice_impl(range)
}

///|
pub fn DocumentSnapshot::line_at_offset(
  self : DocumentSnapshot,
  offset : Int,
) -> Int {
  self.line_at_offset_impl(offset)
}

///|
pub fn DocumentSnapshot::position_at_offset(
  self : DocumentSnapshot,
  offset : Int,
) -> @base_common.Position {
  self.position_at_offset_impl(offset)
}

///|
pub fn DocumentSnapshot::offset_at_position(
  self : DocumentSnapshot,
  position : @base_common.Position,
) -> Int {
  self.offset_at_position_impl(position)
}

///|
pub extend DocumentContent with Debug::{to_repr}

///|
pub extend DocumentError with Debug::{to_repr}

///|
pub extend DocumentReadResult with ToJson::{to_json}

///|
pub extend FileChange with Debug::{to_repr}

///|
pub extend FileChange with ToJson::{to_json}

///|
pub extend FileChangeType with Debug::{to_repr}

///|
pub extend FileChangeType with Eq::{equal, not_equal}

///|
pub extend FileReadResult with Debug::{to_repr}

///|
pub extend FileSystemProviderError with Debug::{to_repr}

///|
pub extend FileSystemProviderError with ToJson::{to_json}

///|
pub extend FileSystemProviderErrorCode with Debug::{to_repr}

///|
pub extend FileSystemProviderErrorCode with Eq::{equal, not_equal}

///|
pub extend SourceError with Debug::{to_repr}

///|
pub extend SourceError with Eq::{equal, not_equal}

///|
pub extend SourcePath with Debug::{to_repr}

///|
pub extend SourcePath with Eq::{equal, not_equal}

///|
pub extend SourcePathResult with Debug::{to_repr}

///|
pub extend SourcePathResult with Eq::{equal, not_equal}

///|
pub extend WatchOptions with Debug::{to_repr}
