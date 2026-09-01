// Filesystem paths are interpreted with the current host's rules. `@path.Path`
// performs that interpretation and may render with backslashes on Windows,
// while URIs, manifests, and the frontend speak forward slashes. `Absolute`
// and `Relative` therefore expose a forward-slash normalized form for those
// boundaries after applying the host's path normalization.

///|
/// A path spelling that has not been classified as absolute or relative.
/// Every string is representable: validation belongs to conversions such as
/// `Path::to_absolute`, not to this transport type.
pub(all) struct Path(String) derive(Debug, Eq)

///|
/// Render the original path spelling at operating-system boundaries.
pub impl Show for Path with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
/// Append a relative path and normalize the result using the current host's
/// path rules. The result remains unclassified because a relative `self` still
/// produces a relative path. Requiring `Relative` makes the caller classify
/// the child instead of silently appending an unclassified path.
pub fn Path::join(self : Path, child : Relative) -> Path {
  Path(@path.Path(self.0).join(Path(child.0)).to_string())
}

///|
/// Resolve this spelling against the current working directory using the
/// current host's path rules. The path library guarantees that the result is
/// absolute, so this conversion does not need an optional result.
pub fn Path::resolve(self : Path) -> Absolute {
  Absolute(@path.Path(self.0).resolve().to_string())
}

///|
/// The current host's directory portion of this path.
pub fn Path::dirname(self : Path) -> Path {
  Path(@path.Path(self.0).dirname().to_string())
}

///|
/// The final component according to the current host's path rules.
pub fn Path::basename(self : Path) -> StringView {
  @path.Path(self.0).basename()
}

///|
/// The final component's extension according to the current host's path
/// rules.
pub fn Path::extname(self : Path) -> StringView {
  @path.Path(self.0).extname()
}

///|
/// Whether the spelling is absolute according to the current host.
pub fn Path::is_host_absolute(self : Path) -> Bool {
  @path.Path(self.0).is_absolute()
}

///|
/// The current-host relative path from `base` to this path.
pub fn Path::relative(self : Path, base~ : Path) -> Path {
  Path(@path.Path(self.0).relative(base=Path(base.0)).to_string())
}

///|
/// A filesystem path that is absolute on the current host. Other packages may
/// inspect and pattern-match the original spelling, but only this package can
/// construct one after validating a `Path`.
pub struct Absolute(String) derive(Debug, Eq, Hash)

///|
/// Render the validated absolute spelling at operating-system boundaries.
pub impl Show for Absolute with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
/// Forget the absolute classification while retaining the spelling.
pub fn Absolute::to_path(self : Absolute) -> Path {
  Path(self.0)
}

///|
/// Encode this host-native absolute path as the slash-rooted path component
/// carried by frontend resource URIs. POSIX paths already have that form;
/// Windows drive paths gain the URI root slash (`C:\\work` -> `/C:/work`).
///
/// UNC and Windows root-relative paths return `None`: a frontend resource URI
/// uses its authority for the owning device, so it has no second authority in
/// which to preserve a UNC server name. Rejecting those spellings keeps this
/// boundary reversible instead of silently changing their destination.
pub fn Absolute::to_uri_path(self : Absolute) -> String? {
  // A double-rooted spelling may carry implementation-defined network
  // semantics even on POSIX. Resource URIs have no authority available for
  // that second identity, so never collapse it into an ordinary local path.
  if @path.sep != '\\' && self.0 is ['/', '/', ..] {
    return None
  }
  let normalized = @path.Path(self.0).normalize().to_string()
  if @path.sep == '\\' {
    let normalized = normalized.replace_all(old="\\", new="/")
    guard normalized is [drive, ':', '/', ..] && drive.is_ascii_path_drive() else {
      return None
    }
    Some("/" + normalized)
  } else {
    Some(normalized)
  }
}

///|
/// Decode a frontend resource URI's slash-rooted path component into an
/// absolute path for this host. Windows accepts only the reversible drive
/// form produced by `Absolute::to_uri_path`; POSIX accepts its ordinary
/// slash-rooted absolute paths. UNC is deliberately outside the transport
/// contract because the URI authority belongs to the device channel.
pub fn Absolute::from_uri_path(path : String) -> Absolute? {
  guard path is ['/', ..] && !(path is ['/', '/', ..]) else { return None }
  if @path.sep == '\\' {
    guard path is ['/', drive, ':', '/', ..] && drive.is_ascii_path_drive() else {
      return None
    }
    Path(path[1:].to_owned()).normalize().to_absolute()
  } else {
    Path(path).normalize().to_absolute()
  }
}

///|
/// Whether this character can name a Windows drive in an absolute path.
fn Char::is_ascii_path_drive(self : Char) -> Bool {
  self is ('a'..='z' | 'A'..='Z')
}

///|
/// Append a relative path and normalize the absolute result using the current
/// host's path rules.
pub fn Absolute::join(self : Absolute, child : Relative) -> Absolute {
  Absolute(self.to_path().join(child).0)
}

///|
/// Convert a path when it is absolute according to the current host. A foreign
/// platform's absolute-path syntax is not accepted because the host filesystem
/// cannot interpret it as that absolute location.
pub fn Path::to_absolute(self : Path) -> Absolute? {
  if self.is_host_absolute() {
    Some(Absolute(self.0))
  } else {
    None
  }
}

///|
/// Convert a path when it is not absolute according to the current host. This
/// classifies input-boundary text before it is appended with `Path::join`.
pub fn Path::to_relative(self : Path) -> Relative? {
  if self.is_host_absolute() {
    None
  } else {
    Some(Relative(self.0))
  }
}

///|
/// Normalize dot segments and redundant separators using the current host's
/// path rules. The returned spelling uses the host's separator.
pub fn Path::normalize(self : Path) -> Path {
  Path(@path.Path(self.0).normalize().to_string())
}

///|
/// A workspace-relative path with forward-slash separators — the form
/// conversations, mention chips, and the file panel name files by. `Relative`
/// asserts provenance rather than validating it: construct it where the path
/// is known relative (a host reply, a tree join), or through
/// `Absolute::relative_to`, the one blessed absolute→relative conversion.
pub(all) struct Relative(String) derive(Debug, Eq, Hash)

///|
/// Render the relative spelling at serialization boundaries.
pub impl Show for Relative with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
/// Forget the relative classification while retaining the spelling.
pub fn Relative::to_path(self : Relative) -> Path {
  Path(self.0)
}

///|
/// The zero-segment relative path: the workspace root itself. Not a sentinel
/// — `""` is the value `relative_to` yields for the root and the parent
/// `child_path`-style joins build from, so it is the root's canonical name.
pub fn Relative::root() -> Relative {
  Relative("")
}

///|
/// Whether this is the workspace root (the zero-segment path).
pub fn Relative::is_root(self : Relative) -> Bool {
  self.0.is_empty()
}

///|
/// Normalize the relative path using the current host's rules, then render it
/// with forward slashes. The zero-segment root remains `Relative("")` rather
/// than the host path library's `"."` spelling.
pub fn Relative::normalize(self : Relative) -> Relative {
  let normalized = Path(self.0).normalize().0
  if normalized == "." {
    Relative::root()
  } else if @path.sep == '\\' {
    // Windows renders its actual separators as backslashes; the frontend and
    // serialized relative form use forward slashes.
    Relative(normalized.replace_all(old="\\", new="/"))
  } else {
    // A backslash is a valid filename character on POSIX, not a separator.
    Relative(normalized)
  }
}

///|
/// Whether `path` is this relative path or one of its descendants, comparing
/// after resolving dot segments and redundant separators with the host's path
/// rules.
pub fn Relative::contains(self : Relative, path : Relative) -> Bool {
  Path(self.0).contains(Path(path.0))
}

///|
/// Normalize the absolute path using the current host's rules, then render it
/// with forward slashes for serialization and comparison.
pub fn Absolute::normalize(self : Absolute) -> Absolute {
  let normalized = Path(self.0).normalize().0
  if @path.sep == '\\' {
    Absolute(normalized.replace_all(old="\\", new="/"))
  } else {
    Absolute(normalized)
  }
}

///|
/// Whether `path` is this absolute path or one of its descendants, comparing
/// after resolving dot segments and redundant separators with the host's path
/// rules.
pub fn Absolute::contains(self : Absolute, path : Absolute) -> Bool {
  Path(self.0).contains(Path(path.0))
}

///|
/// This path relative to the absolute directory `root`: `Some(Relative(""))`
/// when they are the same directory, `Some(Relative("a/b"))` for a
/// descendant, `None` for anything outside. Dot segments and redundant
/// separators are resolved using the host's path rules, including Windows'
/// case-insensitive drive and component comparison. The `None` forces callers
/// to decide what a path outside the workspace means instead of letting an
/// absolute string flow on as if it were relative.
pub fn Absolute::relative_to(self : Absolute, root~ : Absolute) -> Relative? {
  // `@path.Path::relative` owns the platform comparison rules. In particular,
  // its Windows implementation folds path-component case before finding the
  // common prefix; comparing our slash-normalized strings here would reject a
  // real descendant whose drive or directory spelling used different case.
  guard self.to_path().relative(base=root.to_path()).to_relative()
    is Some(relative) else {
    // Windows returns the absolute target when roots/drives differ.
    return None
  }
  let relative = relative.normalize()
  if relative.0 == ".." || relative.0.has_prefix("../") {
    None
  } else {
    Some(relative)
  }
}

///|
/// The unclassified implementation shared by the public absolute and relative
/// containment methods. Keeping it private prevents callers from comparing
/// paths whose classifications do not agree.
fn Path::contains(self : Path, path : Path) -> Bool {
  // Prefix comparison uses one separator after host normalization so the same
  // code works with POSIX and Windows renderings. On POSIX a backslash remains
  // a filename character and must not be interpreted as a separator.
  let path = path.normalize().0
  let root = self.normalize().0
  let (path, root) = if @path.sep == '\\' {
    (path.replace_all(old="\\", new="/"), root.replace_all(old="\\", new="/"))
  } else {
    (path, root)
  }
  if path == root {
    return true
  }
  let prefix = if root.has_suffix("/") { root } else { "\{root}/" }
  path.strip_prefix(prefix) is Some(_)
}

///|
pub extend Absolute with Debug::{to_repr}

///|
pub extend Absolute with Eq::{equal, not_equal}

///|
pub extend Absolute with Hash::{hash, hash_combine}

///|
pub extend Absolute with Show::{output, to_string}

///|
pub extend Path with Debug::{to_repr}

///|
pub extend Path with Eq::{equal, not_equal}

///|
pub extend Path with Show::{output, to_string}

///|
pub extend Relative with Debug::{to_repr}

///|
pub extend Relative with Eq::{equal, not_equal}

///|
pub extend Relative with Hash::{hash, hash_combine}

///|
pub extend Relative with Show::{output, to_string}
