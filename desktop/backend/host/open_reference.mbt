///|
pub struct ResolvedHostReference {
  base : @pathx.Absolute?
  resolution : @openpath.Resolution
}

///|
/// Resolve one transcript path once for both Open and Show in Folder. Keeping
/// cwd fallback, home expansion, position suffixes, and missing-path handling
/// here prevents the two user actions from drifting into different security
/// or path semantics.
pub async fn resolve_host_reference(
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
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  }
  match existing {
    Some(Directory) => raise HostError("\{config} is a directory")
    Some(Regular) => config
    Some(_) => raise HostError("\{config} is not a regular file")
    None => {
      // Recursive mkdir on an existing directory raises EEXIST; the steady
      // state is not an error here any more than in the home preparation.
      @fs.mkdir(home_path.0, recursive=true, permission=0o700) catch {
        @os_error.OSError(_) as error if error.is_EEXIST() => ()
        error => raise error
      }
      @fs.write_file(
        config,
        CodexConfigHeader,
        create_mode=CreateNew,
        permission=0o600,
      ) catch {
        @os_error.OSError(_) as error if error.is_EEXIST() => {
          guard @fs.kind(config) is Regular else {
            raise HostError("\{config} is not a regular file")
          }
        }
        error => raise HostError("Could not create \{config}: \{error}")
      }
      config
    }
  }
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
/// Resolve a file reference on the working machine, without invoking an OS
/// opener. Files can be outside the checkout; directory navigation remains
/// rooted in the current Files tree and must pass lexical and realpath checks.
async fn resolve_reference_op(
  payload : OpenPathPayload,
) -> @protocol.ResolveReferenceReply {
  let reference = match resolve_host_reference(payload) {
    Ok(reference) => reference
    Err(message) => return ReferenceRefused(message~)
  }
  match reference.resolution {
    EditorPath(path~, line~, column~) =>
      ReferenceText(path=reference_uri_path(path), line~, column~)
    BrowserPath(path) => ReferenceBinary(path=reference_uri_path(path))
    SystemPath(path) =>
      if @fs.kind(path) is Directory {
        guard reference.base is Some(root) &&
          @pathx.Path(path).to_absolute() is Some(absolute) &&
          absolute.relative_to(root~) is Some(relative) else {
          return ReferenceRefused(message="Directory is outside this checkout")
        }
        let real_root = @pathx.Path(@fs.realpath(root.to_string())).to_absolute()
        let real_path = @pathx.Path(@fs.realpath(path)).to_absolute()
        guard real_root is Some(real_root) &&
          real_path is Some(real_path) &&
          real_path.relative_to(root=real_root) is Some(_) else {
          return ReferenceRefused(
            message="Directory resolves outside this checkout",
          )
        }
        ReferenceDirectory(path=relative.0)
      } else {
        ReferenceBinary(path=reference_uri_path(path))
      }
    MissingPath(path) =>
      ReferenceRefused(message="File does not exist: \{path}")
  }
}

///|
fn reference_uri_path(path : String) -> String raise {
  guard @pathx.Path(path).to_absolute() is Some(absolute) &&
    absolute.to_uri_path() is Some(uri) else {
    raise HostError("Invalid absolute file path: \{path}")
  }
  uri
}
