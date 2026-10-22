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
/// filenames and every directory write (create, rename, removal) under the
/// root, then re-allows Moon-managed `_build` and `.mooncakes` trees.
///
/// The profile is a fixed handful of rules whatever the tree holds. It used to
/// deny each source-containing directory literally, which scaled with the
/// repository: libsandbox rejects a profile of about 20k such rules and
/// crashes `sandbox-exec` with SIGSEGV at about 40k, so in a large workspace
/// every sandboxed command died before it ran (issue #2158).
///
/// When `writable_lab` is supplied, a final SBPL rule re-allows that entire
/// normalized subtree. This function does not verify that the lab is inside
/// the workspace, so callers must pass only a trusted scratch directory.
///
/// The result is a best-effort write guard, not a complete process-security
/// boundary.
fn source_write_readonly_profile_data(
  real_workspace_root : String,
  writable_lab? : String,
) -> SourceWriteProfileData {
  let root = @workspace_path.strip_trailing_slash(
    @path.Path(real_workspace_root).normalize().to_string(),
  )
  let source_regex = source_write_regex(root)
  let build_carveout_regex = source_write_build_carveout_regex(root)
  let profile = StringBuilder()
  // `file-write*` already covers `file-write-create`, so the regex deny blocks
  // both rewriting existing source and creating new source files. It protects
  // files, not a containing directory: moving `src` out of the workspace would
  // carry its source past the regex. The directory deny closes that, and with
  // it creating or removing a directory, which a read-only role has no reason
  // to do inside the workspace. SBPL is last-match-wins, so the following
  // carve-out re-allows Moon-managed build and cache trees without either deny
  // having to special-case them.
  profile <+
    $|(version 1)
    $|(allow default)
    $|(deny file-write* (regex "\{sbpl_string_escape(source_regex)}"))
    $|(deny file-write* (require-all (subpath "\{sbpl_string_escape(root)}") (vnode-type DIRECTORY)))
    $|(allow file-write* (regex "\{sbpl_string_escape(build_carveout_regex)}"))
    $|
  // SBPL is last-match-wins: one allow-subpath appended AFTER every deny
  // re-opens exactly the lab — a per-child scratch directory where a
  // read-only subagent may scaffold projects and write source to verify
  // claims empirically.
  if writable_lab is Some(lab) {
    let lab = @workspace_path.strip_trailing_slash(
      @path.Path(lab).normalize().to_string(),
    )
    profile <+ "(allow file-write* (subpath \"\{sbpl_string_escape(lab)}\"))\n"
  }
  // A denied directory carries no protected suffix, so the root is what lets a
  // denial of one be recognized: every path the directory rule refuses is
  // below it. Its basename is kept too, for a tool that reports the path as
  // spelled rather than resolved (`/tmp/ws/x` for `/private/tmp/ws/x`).
  {
    profile: profile.to_string(),
    denial_subjects: source_write_denial_subjects([root]),
  }
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
