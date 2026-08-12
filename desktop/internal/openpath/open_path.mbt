// Resolution of transcript file references. UTF-8 text that the built-in
// viewer can load becomes an editor target; other existing paths go to the
// system opener. A trailing `:line[:column]` or `#Lline` is only treated as an
// editor position after the literal path is known not to exist.

///|
/// Keep routing and loading on the same size boundary. Larger files cannot be
/// displayed by the built-in viewer, even when their bytes happen to be text.
pub const MaxEditorFileBytes = 1048576

///|
/// One literal path surfaced by the agent and clicked by the user.
pub(all) struct Reference(String) derive(Debug, Eq)

///|
/// Where the host should send a transcript file reference.
pub(all) enum Resolution {
  // Existing UTF-8 text within the built-in viewer's size limit. Position is
  // absent for an ordinary path and for a real filename ending in a suffix.
  EditorPath(path~ : String, line~ : Int?, column~ : Int?)
  // An existing directory, binary file, or file too large for the viewer.
  SystemPath(String)
  // Neither the literal path nor a parsed suffix-free candidate exists.
  MissingPath(String)
} derive(Debug, Eq)

///|
priv struct EditorCandidate {
  path : String
  line : Int
  column : Int?
}

///|
/// One existing literal or suffix-free path and its optional editor position.
priv struct ExistingPath {
  path : String
  line : Int?
  column : Int?
}

///|
/// Resolve this reference without letting suffix syntax override a real path.
/// Filesystem errors propagate to the host: an unreadable path must not be
/// silently reinterpreted as a different file.
pub async fn Reference::resolve(self : Reference) -> Resolution {
  if @fs.exists(self.0) {
    let existing : ExistingPath = { path: self.0, line: None, column: None }
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
/// the same size limit as the viewer, and invalid UTF-8 is a binary file.
async fn ExistingPath::resolve(self : ExistingPath) -> Resolution {
  guard @fs.kind(self.path) is Regular else { return SystemPath(self.path) }
  let source = @fs.open(self.path, mode=ReadOnly)
  defer source.close()
  guard source.size() <= MaxEditorFileBytes.to_int64() else {
    return SystemPath(self.path)
  }
  let data = source.read_all()
  let raw = data.binary()
  guard raw.find(b"\x00") is None else { return SystemPath(self.path) }
  let text = data.text() catch { _ => return SystemPath(self.path) }
  // A PDF can be entirely ASCII and therefore valid UTF-8, but it is still a
  // formatted binary document rather than source text for the editor.
  guard !text.has_prefix("%PDF-") else { return SystemPath(self.path) }
  EditorPath(path=self.path, line=self.line, column=self.column)
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
      return Some({ path: path.to_owned(), line, column: None })
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
      return Some({ path: path.to_owned(), line, column: Some(last) })
    }
  }
  Some({ path: before_last.to_owned(), line: last, column: None })
}
