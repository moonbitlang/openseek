// Opening a transcript-referenced path: viewer-sized UTF-8 files inside the
// conversation checkout go to the built-in editor; other existing paths go to
// the platform opener. Position suffixes apply only to built-in text files.

///|
async fn open_path_op(payload : OpenPathPayload) -> OpenPathReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall back
  // to the directory the session's engine runs in.
  let base = match payload.cwd {
    Some(cwd) => {
      guard @pathx.Absolute::from_uri_path(cwd) is Some(cwd) else {
        raise HostError("Invalid working directory")
      }
      Some(cwd)
    }
    None => @engine.session_cwd(payload.session)
  }
  guard base is Some(root) else {
    raise HostError("This conversation has no working directory")
  }
  let target = @engine.open_target(
    Some(root),
    @pathx.Path(payload.path).expand_home(),
  )
  guard !target.0.is_empty() else { raise HostError("Empty path") }
  let resolution = @openpath.Reference(target.0).resolve()
  if resolution is MissingPath(path) {
    raise HostError("File does not exist: \{path}")
  }
  if resolution is EditorPath(path~, line~, column~) {
    // The built-in editor is checkout-rooted. Return the relative path we
    // already proved belongs to this exact cwd. Check both the lexical path
    // and its real target so an in-checkout symlink cannot expose text outside
    // the checkout through the editor reader.
    guard @pathx.Path(path).to_absolute() is Some(absolute) &&
      absolute.relative_to(root~) is Some(relative) &&
      !relative.is_root() else {
      raise HostError("Text file is outside the conversation checkout: \{path}")
    }
    let real_root_text = @fs.realpath(root.to_string()) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise HostError("Could not resolve working directory: \{error}")
    }
    let real_path_text = @fs.realpath(path) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise HostError("Could not resolve file: \{error}")
    }
    guard @pathx.Path(real_root_text).to_absolute() is Some(real_root) &&
      @pathx.Path(real_path_text).to_absolute() is Some(real_path) &&
      real_path.relative_to(root=real_root) is Some(real_relative) &&
      !real_relative.is_root() else {
      raise HostError("Text file is outside the conversation checkout: \{path}")
    }
    return {
      opened: false,
      editor_target: Some({ path: relative.0, line, column }),
    }
  }
  guard resolution is SystemPath(system_path) else {
    raise HostError("Could not resolve path")
  }
  let code = @platform.open_path(system_path) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("Could not open \{system_path}: \{error}")
  }
  guard code == 0 else { raise HostError("Could not open \{system_path}") }
  { opened: true, editor_target: None }
}

///|
async test "open_path returns workspace editor positions without a system open" {
  let dir = "_build/host-open-path-editor-test"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
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
  assert_eq(reply, {
    opened: false,
    editor_target: Some({
      path: "source.mbt",
      line: Some(2738),
      column: Some(17),
    }),
  })
  let fragment_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt#L5",
  })
  assert_eq(fragment_reply, {
    opened: false,
    editor_target: Some({ path: "source.mbt", line: Some(5), column: None }),
  })
  let ordinary_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt",
  })
  assert_eq(ordinary_reply, {
    opened: false,
    editor_target: Some({ path: "source.mbt", line: None, column: None }),
  })
  let literal = "\{file}:12"
  @fs.write_file(literal, "literal", create_mode=CreateOrTruncate)
  let literal_reply = open_path_op({
    session: "unused-for-explicit-cwd",
    cwd: Some(cwd),
    path: "source.mbt:12",
  })
  assert_eq(literal_reply, {
    opened: false,
    editor_target: Some({ path: "source.mbt:12", line: None, column: None }),
  })
}

///|
async test "open_path rejects missing and outside text files" {
  let dir = "_build/host-open-path-boundary-test"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
  let cwd = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  let mut missing = false
  ignore(
    open_path_op({
      session: "unused-for-explicit-cwd",
      cwd: Some(cwd),
      path: "missing.mbt:12",
    }),
  ) catch {
    HostError(message) => missing = message.has_prefix("File does not exist:")
    _ => ()
  }
  assert_true(missing)
  let outside = "_build/host-open-path-outside.txt"
  @fs.write_file(outside, "outside", create_mode=CreateOrTruncate)
  let outside = @fs.realpath(outside)
  let mut escaped = false
  ignore(
    open_path_op({
      session: "unused-for-explicit-cwd",
      cwd: Some(cwd),
      path: outside,
    }),
  ) catch {
    HostError(message) =>
      escaped = message.has_prefix(
        "Text file is outside the conversation checkout:",
      )
    _ => ()
  }
  assert_true(escaped)
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
