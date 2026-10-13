// Resolution of file references. Viewer-sized text opens in the editor;
// Office documents and PDFs open in the file panel; raster images open in the
// browser. Other existing paths go to the system application.
// A trailing `:line[:column]` or `#Lline` is
// only treated as an editor position after the literal path is known not to exist.

///|
/// Keep routing and loading on the same size boundary. Larger files cannot be
/// displayed by the built-in viewer, even when their bytes happen to be text.
pub const MaxEditorFileBytes = 1048576

///|
/// Office packages and PDFs need their original bytes for the read-only
/// document viewer. Keep their limit separate from the
/// text editor limit so a normal document is not rejected merely because its
/// embedded media makes the package larger than one megabyte.
// Keep the decoded package below the 32 MiB remote JSON frame limit after
// base64 expansion and JSON overhead.
pub const MaxOfficeFileBytes : Int32 = 20 * 1024 * 1024

///|
/// One literal path surfaced by the agent and clicked by the user.
pub(all) struct Reference(String) derive(Debug, Eq)

///|
/// Where the host should send a transcript file reference.
pub(all) enum Resolution {
  // UTF-8 text within the viewer's size limit.
  // Position is absent for an ordinary path and a real filename with a suffix.
  EditorPath(path~ : String, line~ : Int32?, column~ : Int32?)
  // A supported raster image, identified by its header independently
  // of the text viewer size limit.
  BrowserPath(String)
  // An existing directory, other binary file, or text too large for the viewer.
  SystemPath(String)
  // Neither the literal path nor a parsed suffix-free candidate exists.
  MissingPath(String)
} derive(Debug, Eq)

///|
priv struct EditorCandidate {
  path : String
  line : Int32
  column : Int32?
}

///|
/// One existing literal or suffix-free path and its optional editor position.
priv struct ExistingPath {
  path : String
  line : Int32?
  column : Int32?
}

///|
/// Resolve this reference without letting suffix syntax override a real path.
/// Filesystem errors propagate to the host: an unreadable path must not be
/// silently reinterpreted as a different file.
pub async fn Reference::resolve(self : Reference) -> Resolution {
  if @fs.exists(self.0) {
    let existing : ExistingPath = { path: self.0, line: None, column: None, }
    return existing.resolve()
  }
  guard self.editor_candidate() is Some(candidate) else {
    return MissingPath(self.0)
  }
  guard @fs.exists(candidate.path) else { return MissingPath(candidate.path) }
  let existing : ExistingPath = {
    path: candidate.path,
    line: Some(candidate.line),
    column: candidate.column,
  }
  existing.resolve()
}

///|
/// Apply the built-in viewer's actual content contract. Reading is bounded by
/// the same size limit as the viewer; the shared file-kind policy keeps this
/// routing decision identical to the host's eventual file reply.
async fn ExistingPath::resolve(self : ExistingPath) -> Resolution {
  guard @fs.kind(self.path) is Regular else { return SystemPath(self.path) }
  let source = @fs.open(self.path, mode=ReadOnly)
  defer source.close()
  let office = is_office_path(self.path)
  let size = source.size()
  if !office {
    // Twelve bytes cover every supported raster signature, including WebP.
    let header_size = if size < 12 { size.to_int() } else { 12 }
    let header = source.read_exactly_at(header_size, position=0)
    match @filekind.classify(header) {
      Pdf => {
        guard size <= MaxOfficeFileBytes.to_int64() else {
          return SystemPath(self.path)
        }
        return EditorPath(path=self.path, line=self.line, column=self.column)
      }
      Image(_) => return BrowserPath(self.path)
      _ => ()
    }
  }
  let size_limit = if office { MaxOfficeFileBytes } else { MaxEditorFileBytes }
  guard size <= size_limit.to_int64() else { return SystemPath(self.path) }
  if office {
    return EditorPath(path=self.path, line=self.line, column=self.column)
  }
  let data = source.read_all()
  match @filekind.classify(data.binary()) {
    Utf8Text(_) =>
      EditorPath(path=self.path, line=self.line, column=self.column)
    Pdf => EditorPath(path=self.path, line=self.line, column=self.column)
    Image(_) => BrowserPath(self.path)
    UnknownBinary => SystemPath(self.path)
  }
}

///|
/// Document extensions route to the file panel. Its Office reader or PDF.js
/// validates the original bytes before showing the document.
fn is_office_path(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".docx") ||
  lower.has_suffix(".xlsx") ||
  lower.has_suffix(".pdf")
}

///|
/// Parse conventional editor-position suffixes. A Markdown destination may use
/// GitHub's `#Lline`; colon positions are parsed from right to left, and the
/// second numeric component is a column only when the preceding component is
/// also a positive integer. This keeps a Windows drive colon and ordinary
/// colons in the path.
fn Reference::editor_candidate(self : Reference) -> EditorCandidate? {
  if self.0.rev_split_once("#L") is Some((path, line_text)) {
    let line = @string.parse_int(line_text, base=10) catch { _ => 0 }
    if line > 0 && !path.is_empty() {
      return Some({ path: path.to_owned(), line, column: None, })
    }
  }
  guard self.0.rev_split_once(":") is Some((before_last, last_text)) else {
    return None
  }
  let last = @string.parse_int(last_text, base=10) catch { _ => 0 }
  guard last > 0 && !before_last.is_empty() else { return None }
  if before_last.rev_split_once(":") is Some((path, line_text)) {
    let line = @string.parse_int(line_text, base=10) catch { _ => 0 }
    if line > 0 && !path.is_empty() {
      return Some({ path: path.to_owned(), line, column: Some(last), })
    }
  }
  Some({ path: before_last.to_owned(), line: last, column: None, })
}

///|
pub extend Reference with Debug::{to_repr}

///|
pub extend Reference with Eq::{equal, not_equal}

///|
pub extend Resolution with Debug::{to_repr}

///|
pub extend Resolution with Eq::{equal, not_equal}
