///|
/// Return whether `target` is lexically inside `lab`, including the lab itself.
///
/// Both paths are normalized before comparison. An empty lab and the
/// filesystem root `/` are rejected so this predicate cannot accidentally
/// authorize every path. No filesystem or symlink resolution is performed.
pub fn path_is_under_lab(target : String, lab : String) -> Bool {
  let lab = @workspace_path.strip_trailing_slash(
    @path.Path(lab).normalize().to_string(),
  )
  guard !lab.is_empty() && lab != "/" else { return false }
  let target = @workspace_path.strip_trailing_slash(
    @path.Path(target).normalize().to_string(),
  )
  target == lab || target.has_prefix("\{lab}/")
}

///|
/// Return whether `target` is a protected MoonBit source path inside the
/// workspace.
///
/// The root and target are lexically normalized, containment is inclusive,
/// protected names are recognized by `is_protected_source_path`, and paths
/// below `_build` or `.mooncakes` are excluded. The root should already be a
/// canonical path when this predicate is used to mirror SBPL behavior.
pub fn is_protected_workspace_source_path(
  real_workspace_root : String,
  target : String,
) -> Bool {
  let root = @workspace_path.strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let target = @path.Path(target).normalize().to_string()
  @workspace_path.is_under_workspace_root(root, target) &&
  !is_moon_managed_workspace_path(root, target) &&
  is_protected_source_path(target)
}

///|
/// Return whether `path` is below an `_build` or `.mooncakes` directory within
/// `root`.
///
/// The root itself is never considered Moon-managed. Comparison is
/// case-sensitive and lexical; separators and trailing slashes are normalized,
/// but callers must normalize `.` and `..` components first.
pub fn is_moon_managed_workspace_path(root : String, path : String) -> Bool {
  let root = workspace_compare_path(root)
  let path = workspace_compare_path(path)
  if path == root {
    return false
  }
  if !@workspace_path.is_under_workspace_root(root, path) {
    return false
  }
  let relative_start = if root == "/" { 1 } else { root.length() + 1 }
  path[relative_start:]
  .split("/")
  .any(part => part is ("_build" | ".mooncakes"))
}

///|
fn workspace_compare_path(path : String) -> String {
  @workspace_path.strip_trailing_slash(path.replace_all(old="\\", new="/"))
}

///|
/// Return whether `path` has a protected MoonBit source or manifest name.
///
/// Protected names are `*.mbt`, `*.mbti`, `*.mbt.md`, `moon.mod`, `moon.pkg`,
/// `moon.work`, and the legacy JSON manifests. Matching is case-sensitive,
/// purely lexical, and accepts either a basename or a full path.
pub fn is_protected_source_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path.has_suffix(".mbt.md") ||
  path.has_suffix(".mbt") ||
  path.has_suffix(".mbti") ||
  // A bare basename and a full path are both accepted, so each manifest name
  // is matched either whole or as the last component. Deliberately NOT via
  // `path_basename`: that strips a trailing slash, and callers hand this raw
  // shell arguments where `pkg/moon.pkg/` names a directory, not the manifest.
  protected_manifest_names.any(name => {
    path == name || path.has_suffix("/\{name}")
  })
}

///|
/// The manifest filenames `is_protected_source_path` guards, current and
/// legacy-JSON spellings alike.
let protected_manifest_names : Array[String] = [
  "moon.mod", "moon.pkg", "moon.work", "moon.mod.json", "moon.pkg.json",
]
