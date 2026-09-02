// Opening a transcript-referenced path: viewer-sized UTF-8 files inside the
// conversation checkout go to the built-in editor, checkout-local directories
// go to its Files tree, and other existing paths go to the platform opener.
// Position suffixes apply only to built-in text files.

///|
priv struct ResolvedHostReference {
  base : @pathx.Absolute?
  resolution : @openpath.Resolution
}

///|
/// Resolve one transcript path once for both Open and Show in Folder. Keeping
/// cwd fallback, home expansion, position suffixes, and missing-path handling
/// here prevents the two user actions from drifting into different security
/// or path semantics.
async fn resolve_host_reference(
  payload : OpenPathPayload,
) -> Result[ResolvedHostReference, String] {
  // A live run hands us its cwd; a resumed conversation has none, so fall back
  // to the directory the session's engine runs in.
  let base = match payload.cwd {
    Some(cwd) => {
      guard @pathx.Absolute::from_uri_path(cwd) is Some(cwd) else {
        return Err("Invalid working directory")
      }
      Some(cwd)
    }
    None => @work_dir.session_cwd(payload.session)
  }
  let path = @pathx.Path(payload.path).expand_home()
  // Absolute system targets do not need a conversation checkout. Relative
  // paths still need one so they never fall back to the host process's cwd.
  if base is None && !path.is_host_absolute() {
    return Err("This conversation has no working directory")
  }
  let target = @work_dir.open_target(base, path)
  guard !target.0.is_empty() else { return Err("Empty path") }
  let resolution = @openpath.Reference(target.0).resolve()
  if resolution is MissingPath(path) {
    return Err("File does not exist: \{path}")
  }
  Ok({ base, resolution, })
}

///|
/// Refusals travel inside the reply as `Refused(message)` rather than as a
/// raised error: the local bridge flattens a raise to the generic
/// "op ext:openseek/host.open_path failed" and hides the reason.
async fn open_path_op(payload : OpenPathPayload) -> OpenPathReply {
  let reference = match resolve_host_reference(payload) {
    Ok(reference) => reference
    Err(message) => return refusal(message)
  }
  let base = reference.base
  let resolution = reference.resolution
  if resolution is EditorPath(path~, line~, column~) {
    guard base is Some(root) else {
      return refusal("This conversation has no working directory")
    }
    // The built-in editor is checkout-rooted. Return the relative path we
    // already proved belongs to this exact cwd. Check both the lexical path
    // and its real target so an in-checkout symlink cannot expose text outside
    // the checkout through the editor reader.
    guard @pathx.Path(path).to_absolute() is Some(absolute) &&
      absolute.relative_to(root~) is Some(relative) &&
      !relative.is_root() else {
      return refusal("Text file is outside the conversation checkout: \{path}")
    }
    let real_root_text = @fs.realpath(root.to_string()) catch {
      error if @async.is_being_cancelled() => raise error
      error => return refusal("Could not resolve working directory: \{error}")
    }
    let real_path_text = @fs.realpath(path) catch {
      error if @async.is_being_cancelled() => raise error
      error => return refusal("Could not resolve file: \{error}")
    }
    guard @pathx.Path(real_root_text).to_absolute() is Some(real_root) &&
      @pathx.Path(real_path_text).to_absolute() is Some(real_path) &&
      real_path.relative_to(root=real_root) is Some(real_relative) &&
      !real_relative.is_root() else {
      return refusal("Text file is outside the conversation checkout: \{path}")
    }
    return Editor({ path: relative.0, line, column, })
  }
  guard resolution is SystemPath(system_path) else {
    return refusal("Could not resolve path")
  }
  // A literal directory inside this conversation belongs to the built-in Files
  // tree, except for macOS application bundles, which belong to LaunchServices.
  // Check both its lexical and real path so an in-checkout symlink cannot expose
  // a directory outside the checkout. Files retain the upstream text
  // classification above; other paths retain the system-opener policy.
  if base is Some(root) &&
    @pathx.Path(system_path).to_absolute() is Some(absolute) &&
    absolute.relative_to(root~) is Some(relative) {
    let kind = Some(@fs.kind(system_path)) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    if kind is Some(Directory) &&
      should_reveal_checkout_directory(
        system_path,
        is_darwin=@platform.is_darwin(),
      ) {
      let real_root_text = Some(@fs.realpath(root.to_string())) catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      }
      let real_path_text = Some(@fs.realpath(system_path)) catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      }
      if real_root_text is Some(real_root_text) &&
        real_path_text is Some(real_path_text) &&
        @pathx.Path(real_root_text).to_absolute() is Some(real_root) &&
        @pathx.Path(real_path_text).to_absolute() is Some(real_path) &&
        real_path.relative_to(root=real_root) is Some(_) {
        return Directory({ path: relative.0, })
      }
    }
  }
  let code = @platform.open_path(system_path) catch {
    error if @async.is_being_cancelled() => raise error
    error => return refusal("Could not open \{system_path}: \{error}")
  }
  guard code == 0 else { return refusal("Could not open \{system_path}") }
  Opened
}

///|
/// Resolve and reveal the same path that `open_path` would route, but never
/// substitute the built-in editor or a default application for the file
/// manager. Position suffixes identify the underlying file.
async fn reveal_path_op(payload : OpenPathPayload) -> RevealPathReply {
  let reference = match resolve_host_reference(payload) {
    Ok(reference) => reference
    Err(message) => return RevealRefused(message)
  }
  let path = match reference.resolution {
    EditorPath(path~, ..) => path
    SystemPath(path) => path
    MissingPath(path) => return RevealRefused("File does not exist: \{path}")
  }
  let code = @platform.reveal_path(path) catch {
    error if @async.is_being_cancelled() => raise error
    error => return RevealRefused("Could not show \{path}: \{error}")
  }
  if code == 0 {
    Revealed
  } else {
    RevealRefused("Could not show \{path}")
  }
}

///|
async test "reveal_path shares open_path reference refusals" {
  let root = @fs.tmpdir(prefix="openseek-host-reveal-missing-")
  let missing = "\{root}/missing.mbt:12"
  let reply = reveal_path_op({
    session: "unused-for-absolute-path",
    cwd: None,
    path: missing,
  })
  assert_eq(reply, RevealRefused("File does not exist: \{root}/missing.mbt"))
}

///|
async fn should_reveal_checkout_directory(
  path : String,
  is_darwin~ : Bool,
) -> Bool {
  guard is_darwin && path.has_suffix(".app") else { return true }
  let info_plist = "\{path}/Contents/Info.plist"
  let info_kind = Some(@fs.kind(info_plist)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
  !(info_kind is Some(Regular))
}

///|
/// A refusal travels inside the reply instead of raising: the local bridge
/// flattens a raised host error to the generic
/// "op ext:openseek/host.open_path failed" and hides this message.
fn refusal(message : String) -> OpenPathReply {
  Refused(message)
}

///|
#cfg(not(platform="windows"))
async test "open_path only requires a working directory for relative or editor paths" {
  let root = @fs.tmpdir(prefix="openseek-host-open-without-cwd-")
  let missing_path = "\{root}/missing.bin"
  // The absolute target reached the existence check (not the working-
  // directory gate), proving it was treated as an absolute system path.
  let absolute_missing = open_path_op({
    session: "",
    cwd: None,
    path: missing_path,
  })
  assert_eq(absolute_missing, Refused("File does not exist: \{missing_path}"))
  let relative_missing = open_path_op({
    session: "",
    cwd: None,
    path: "missing.bin",
  })
  assert_eq(
    relative_missing,
    Refused("This conversation has no working directory"),
  )
  let text_path = "\{root}/source.mbt"
  @fs.write_file(text_path, "fn main {}", create_mode=CreateOrTruncate)
  let editor_without_cwd = open_path_op({
    session: "",
    cwd: None,
    path: text_path,
  })
  assert_eq(
    editor_without_cwd,
    Refused("This conversation has no working directory"),
  )
}

///|
#cfg(not(platform="windows"))
async test "open_path returns workspace editor positions without a system open" {
  // A kernel-created directory keeps concurrent package tests from racing to
  // create the shared `_build` parent.
  let dir = @fs.tmpdir(prefix="openseek-host-open-editor-")
  let file = "\{dir}/source.mbt"
  @fs.write_file(file, "fn main {}", create_mode=CreateOrTruncate)
  let cwd = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt:2738:17",
  })
  assert_eq(
    reply,
    Editor({ path: "source.mbt", line: Some(2738), column: Some(17), }),
  )
  let fragment_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt#L5",
  })
  assert_eq(
    fragment_reply,
    Editor({ path: "source.mbt", line: Some(5), column: None, }),
  )
  let ordinary_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt",
  })
  assert_eq(
    ordinary_reply,
    Editor({ path: "source.mbt", line: None, column: None, }),
  )
  let literal = "\{file}:12"
  @fs.write_file(literal, "literal", create_mode=CreateOrTruncate)
  let literal_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt:12",
  })
  assert_eq(
    literal_reply,
    Editor({ path: "source.mbt:12", line: None, column: None, }),
  )
  @fs.mkdir("\{dir}/src")
  let directory_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "src",
  })
  assert_eq(directory_reply, Directory({ path: "src", }))
}

///|
async test "macOS application bundles bypass the workspace Files tree" {
  let dir = @fs.tmpdir(prefix="openseek-host-open-app-bundle-")
  let bundle = "\{dir}/SeekMoon.app"
  @fs.mkdir("\{bundle}/Contents", recursive=true)
  @fs.write_file(
    "\{bundle}/Contents/Info.plist",
    "<?xml version=\"1.0\"?>",
    create_mode=CreateOrTruncate,
  )
  assert_false(should_reveal_checkout_directory(bundle, is_darwin=true))
  assert_true(should_reveal_checkout_directory(bundle, is_darwin=false))
  let suffix_only = "\{dir}/NotAnApplication.app"
  @fs.mkdir(suffix_only)
  assert_true(should_reveal_checkout_directory(suffix_only, is_darwin=true))
}

///|
async test "open_path rejects missing and outside text files" {
  let root = @fs.tmpdir(prefix="openseek-host-open-boundary-")
  let dir = "\{root}/workspace"
  @fs.mkdir(dir)
  let cwd = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let missing = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "missing.mbt:12",
  })
  assert_true(
    missing is Refused(message) && message.has_prefix("File does not exist:"),
  )
  let outside = "\{root}/outside.txt"
  @fs.write_file(outside, "outside", create_mode=CreateOrTruncate)
  let outside = @fs.realpath(outside)
  let escaped = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: outside,
  })
  assert_true(
    escaped is Refused(message) &&
    message.has_prefix("Text file is outside the conversation checkout:"),
  )
}

///|
/// Expand a leading `~` (the agent often writes paths home-relative) to the
/// user's home directory; other paths pass through for `open_target` to take
/// against the working directory. Keeping this on `Path` preserves the
/// unclassified input until `open_target` decides whether it is absolute.
fn @pathx.Path::expand_home(self : @pathx.Path) -> @pathx.Path {
  if self.0 == "~" && @home.dir() is Some(home) {
    home
  } else if self.0.strip_prefix("~/") is Some(rest) && @home.dir() is Some(home) {
    home.join(Relative(rest.to_owned()))
  } else {
    self
  }
}

///|
/// Seed content for a `config.toml` this desktop creates. Codex treats an
/// empty file as default configuration, so the header only orients whoever
/// opens it.
const CodexConfigHeader : String = "# Codex configuration for this desktop's CODEX_HOME.\n# Reference: https://github.com/openai/codex/blob/main/docs/config.md\n# The Codex app-server reads this file at startup; restart the desktop to\n# apply edits.\n"

///|
/// The Codex home's `config.toml`, created (with its home directory) when
/// missing so the Settings button works on a fresh home before Codex writes
/// anything. Without an isolated home the CLI's own resolution applies: the
/// inherited `CODEX_HOME`, or `~/.codex`.
pub async fn ensure_codex_config(home : @pathx.Path?) -> String {
  let home_path : @pathx.Path = match home {
    Some(home) => home
    None =>
      match @sys.get_env_var("CODEX_HOME") {
        Some(value) if !value.is_blank() => Path(value)
        _ => @pathx.Path("~/.codex").expand_home()
      }
  }
  let config = "\{home_path.0}/config.toml"
  let existing = Some(@fs.kind(config)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
  match existing {
    Some(Directory) => raise HostError("\{config} is a directory")
    Some(_) => config
    None => {
      // Recursive mkdir on an existing directory raises EEXIST; the steady
      // state is not an error here any more than in the home preparation.
      @fs.mkdir(home_path.0, recursive=true) catch {
        error if @async.is_being_cancelled() => raise error
        _ => ()
      }
      @fs.write_file(config, CodexConfigHeader, create_mode=CreateNew) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise HostError("Could not create \{config}: \{error}")
      }
      config
    }
  }
}

///|
/// Ensure and open the Codex home's `config.toml` with the platform opener.
pub async fn open_codex_config(home : @pathx.Path?) -> Unit {
  let config = ensure_codex_config(home)
  let code = @platform.open_path(config) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("Could not open \{config}: \{error}")
  }
  guard code == 0 else { raise HostError("Could not open \{config}") }
}

///|
async test "ensure_codex_config creates the file once and keeps edits" {
  let home = @fs.tmpdir(prefix="openseek-codex-config-")
  let nested = @pathx.Path("\{home}/isolated/codex")
  let created = ensure_codex_config(Some(nested))
  assert_eq(created, "\{home}/isolated/codex/config.toml")
  let seeded = @fs.read_file(created).text()
  assert_true(seeded.has_prefix("# Codex configuration"))
  // A later call returns the same path without touching user edits.
  @fs.write_file(created, "model = \"gpt-5.4\"\n", create_mode=CreateOrTruncate)
  let again = ensure_codex_config(Some(nested))
  assert_eq(again, created)
  assert_eq(@fs.read_file(created).text(), "model = \"gpt-5.4\"\n")
}
