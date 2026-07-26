///|
let source_write_profile_cache : Map[String, CachedSourceWriteProfile] = Map([])

///|
priv struct WatchedSourceProfileDir {
  path : String
  mtime_s : Int64
  mtime_ns : Int
}

///|
priv struct SourceWriteProfileScan {
  literal_paths : Array[String]
  watched_dirs : Array[WatchedSourceProfileDir]
  cacheable : Bool
}

///|
priv struct SourceWriteProfileScanBuilder {
  literal_paths : Array[String]
  watched_dirs : Array[WatchedSourceProfileDir]
  mut cacheable : Bool
}

///|
priv struct CachedSourceWriteProfile {
  profile : String
  watched_dirs : Array[WatchedSourceProfileDir]
  denial_subjects : Array[String]
}

///|
/// A source-write protection profile and the subjects used to diagnose its
/// denials.
///
/// `profile` is complete SBPL source suitable for `sandbox_exec_args`.
/// `denial_subjects` contains protected directory paths and basenames that
/// `source_write_denied_in_text` can match in child-process output.
priv struct SourceWriteProfileData {
  /// Complete SBPL source passed to `sandbox_exec_args`.
  profile : String
  /// Protected paths and basenames used to recognize denial diagnostics.
  denial_subjects : Array[String]
}

///|
/// Build an SBPL profile that denies writes to protected MoonBit source paths
/// under `real_workspace_root` while allowing reads and other writes.
///
/// `real_workspace_root` should be an absolute, canonical filesystem path:
/// SBPL evaluates file operations against resolved paths, but this function
/// only performs lexical normalization. The profile denies protected source
/// filenames and source-containing directories, then re-allows Moon-managed
/// `_build` and `.mooncakes` trees.
///
/// When `writable_lab` is supplied, a final SBPL rule re-allows that entire
/// normalized subtree. This function does not verify that the lab is inside
/// the workspace, so callers must pass only a trusted scratch directory.
///
/// Base profiles are cached by normalized workspace root. Directory mtimes
/// invalidate cached scans when the protected source tree changes. The result
/// is a best-effort write guard, not a complete process-security boundary.
async fn source_write_readonly_profile_data(
  real_workspace_root : String,
  writable_lab? : String,
) -> SourceWriteProfileData {
  let base = source_write_readonly_profile_base(real_workspace_root)
  match writable_lab {
    None => base
    // SBPL is last-match-wins: one allow-subpath appended AFTER every deny
    // re-opens exactly the lab — a per-child scratch directory where a
    // read-only subagent may scaffold projects and write source to verify
    // claims empirically. The composed profile is not cached (labs are
    // per-child temp dirs); the base underneath still is.
    Some(lab) => {
      let lab = @workspace_path.strip_trailing_slash(
        @path.Path(lab).normalize().to_string(),
      )
      {
        profile: "\{base.profile}(allow file-write* (subpath \"\{sbpl_string_escape(lab)}\"))\n",
        denial_subjects: base.denial_subjects,
      }
    }
  }
}

///|
async fn source_write_readonly_profile_base(
  real_workspace_root : String,
) -> SourceWriteProfileData {
  let real_workspace_root = @workspace_path.strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  match source_write_profile_cache.get(real_workspace_root) {
    Some(cached) if cached_source_write_profile_valid(cached) =>
      return {
        profile: cached.profile,
        denial_subjects: cached.denial_subjects,
      }
    Some(_) => ()
    None => ()
  }
  let scan = protected_source_tree_profile_scan(real_workspace_root)
  let denial_subjects = source_write_denial_subjects(scan.literal_paths)
  let source_regex = source_write_regex(real_workspace_root)
  let build_carveout_regex = source_write_build_carveout_regex(
    real_workspace_root,
  )
  let profile = StringBuilder()
  // `file-write*` already covers `file-write-create`, so this single deny blocks
  // both rewriting existing source and creating new source files. SBPL is
  // last-match-wins, so the following carve-out re-allows Moon-managed build and
  // cache trees without the deny regex having to special-case them.
  profile <+
    $|(version 1)
    $|(allow default)
    $|(deny file-write* (regex "\{sbpl_string_escape(source_regex)}"))
    $|(allow file-write* (regex "\{sbpl_string_escape(build_carveout_regex)}"))
    $|
  for dir in scan.literal_paths {
    profile <+
      $|(deny file-write* (literal "\{sbpl_string_escape(dir)}"))
      $|
  }
  let profile = profile.to_string()
  if scan.cacheable {
    source_write_profile_cache[real_workspace_root] = {
      profile,
      watched_dirs: scan.watched_dirs,
      denial_subjects,
    }
  }
  { profile, denial_subjects }
}

///|
fn source_write_denial_subjects(literal_paths : Array[String]) -> Array[String] {
  let subjects : Array[String] = []
  for path in literal_paths {
    subjects.push(path)
    let base = @workspace_path.path_basename(path)
    if base != path {
      subjects.push(base)
    }
  }
  subjects
}

///|
async fn cached_source_write_profile_valid(
  cached : CachedSourceWriteProfile,
) -> Bool {
  for watched in cached.watched_dirs {
    let (mtime_s, mtime_ns) = @fs.mtime(watched.path, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return false
    }
    if mtime_s != watched.mtime_s || mtime_ns != watched.mtime_ns {
      return false
    }
  }
  true
}

///|
fn source_write_regex(real_workspace_root : String) -> String {
  let root = regex_escape(
    @workspace_path.strip_trailing_slash(real_workspace_root),
  )
  let source_file = "([^/]*(\\.mbt\\.md|\\.mbt|\\.mbti)|(moon\\.mod\\.json|moon\\.pkg\\.json|moon\\.mod|moon\\.pkg|moon\\.work))"
  "^\{root}(/|$)(.*/)?\{source_file}$"
}

///|
/// Paths under a Moon-managed `_build` or `.mooncakes` directory, where Moon
/// itself writes generated `.mbt` sources. Emitted as an `allow` rule after the
/// source deny so the sandbox blocks hand-written source rewrites while leaving
/// Moon's own build/cache writes untouched. Mirrors the component names in
/// `is_moon_managed_workspace_path`.
fn source_write_build_carveout_regex(real_workspace_root : String) -> String {
  let root = regex_escape(
    @workspace_path.strip_trailing_slash(real_workspace_root),
  )
  "^\{root}/(.*/)?(_build|\\.mooncakes)(/|$)"
}

///|
async fn protected_source_tree_profile_scan(
  real_workspace_root : String,
) -> SourceWriteProfileScan {
  let root = @workspace_path.strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let state : SourceWriteProfileScanBuilder = {
    literal_paths: [],
    watched_dirs: [],
    cacheable: true,
  }
  ignore(collect_protected_source_tree_profile_scan(root, root, state))
  {
    literal_paths: state.literal_paths,
    watched_dirs: state.watched_dirs,
    cacheable: state.cacheable,
  }
}

///|
async fn collect_protected_source_tree_profile_scan(
  root : String,
  dir : String,
  state : SourceWriteProfileScanBuilder,
) -> Bool {
  if dir != root &&
    @source_write_policy.is_moon_managed_workspace_path(root, dir) {
    return false
  }
  if dir != root && should_prune_profile_scan_path(root, dir) {
    return false
  }
  let (mtime_s, mtime_ns) = @fs.mtime(dir, follow_symlink=false) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      state.cacheable = false
      return false
    }
  }
  state.watched_dirs.push({ path: dir, mtime_s, mtime_ns })
  let entries = @fs.readdir(dir, include_hidden=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      state.cacheable = false
      return false
    }
  }
  let mut contains_protected = false
  for entry in entries {
    let child = @path.Path(dir).join(Path(entry)).normalize().to_string()
    if @source_write_policy.is_moon_managed_workspace_path(root, child) {
      continue
    }
    if @source_write_policy.is_protected_workspace_source_path(root, child) {
      contains_protected = true
      continue
    }
    let kind = @fs.kind(child, follow_symlink=false) catch {
      error if @async.is_being_cancelled() => raise error
      _ => {
        state.cacheable = false
        continue
      }
    }
    match kind {
      Directory =>
        if collect_protected_source_tree_profile_scan(root, child, state) {
          contains_protected = true
        }
      _ => ()
    }
  }
  if contains_protected && dir != root {
    state.literal_paths.push(dir)
  }
  contains_protected
}

///|
fn should_prune_profile_scan_path(root : String, path : String) -> Bool {
  guard @workspace_path.is_under_workspace_root(root, path) && path != root else {
    return false
  }
  let relative = path[root.length() + 1:].to_owned()
  relative
  .replace_all(old="\\", new="/")
  .split("/")
  .any(part => part is (".git" | ".hg" | ".svn" | ".jj" | "node_modules"))
}

///|
fn regex_escape(text : String) -> String {
  let escaped = StringBuilder()
  for ch in text {
    match ch {
      '\\'
      | '.'
      | '+'
      | '*'
      | '?'
      | '^'
      | '$'
      | '('
      | ')'
      | '['
      | ']'
      | '{'
      | '}'
      | '|'
      | '/' => escaped <+ "\\\{ch}"
      _ => escaped <+ "\{ch}"
    }
  }
  escaped.to_string()
}

///|
/// Escape text for the contents of an SBPL quoted string.
///
/// Quotes, backslashes, newlines, carriage returns, and tabs are escaped. The
/// returned text does not include surrounding quotes and is not a complete
/// SBPL expression.
fn sbpl_string_escape(text : String) -> String {
  let escaped = StringBuilder()
  for ch in text {
    match ch {
      '"' | '\\' => escaped <+ "\\\{ch}"
      '\n' => escaped <+ "\\n"
      '\r' => escaped <+ "\\r"
      '\t' => escaped <+ "\\t"
      _ => escaped <+ "\{ch}"
    }
  }
  escaped.to_string()
}
