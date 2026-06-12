///|
const FrontendEntryPath = "assets/index.html"

///|
const DefaultEngine = "openseek"

///|
/// Locate the bundled frontend entry relative to the executable. On macOS
/// the assets live in `Contents/Resources/` — `Contents/MacOS/` may only
/// hold code, since non-`--deep` codesigning rejects data files there — so
/// probe `../Resources/` first; the executable-adjacent layout serves the
/// Linux AppImage and bare dev builds. Falls back to a cwd-relative path
/// for `moon run` during development.
pub fn frontend_entry_path(framework_command : String) -> String {
  let command_dir : @mbpath.Path = (framework_command : @mbpath.Path)
    .dirname()
    .resolve()
  let candidates = [
    command_dir.join("..").join("Resources").join(FrontendEntryPath),
    command_dir.join(FrontendEntryPath),
  ]
  for candidate in candidates {
    let path = candidate.normalize().to_string()
    if @mbfs.path_exists(path) {
      return path
    }
  }
  FrontendEntryPath
}

///|
fn bundled_engine_path(framework_command : String) -> String? {
  let command_path : @mbpath.Path = framework_command
  let command_dir = command_path.dirname().resolve()
  let candidates = match @env.get_env_var("OS") {
    Some("Windows_NT") => ["openseek.exe", "openseek"]
    _ => ["openseek", "openseek.exe"]
  }
  for candidate in candidates {
    let path = command_dir.join(candidate).normalize().to_string()
    if @mbfs.path_exists(path) {
      return Some(path)
    }
  }
  None
}

///|
/// The engine executable to run: the one bundled beside the host binary, or
/// the `OPENSEEK_ENGINE` override, or `openseek` on PATH.
pub fn engine_command(framework_command : String) -> String {
  if bundled_engine_path(framework_command) is Some(path) {
    return path
  }
  non_empty(@env.get_env_var("OPENSEEK_ENGINE")).unwrap_or(DefaultEngine)
}

///|
fn launch_log_path(framework_command : String) -> String {
  let command_path : @mbpath.Path = framework_command
  command_path
  .dirname()
  .resolve()
  .join("openseek-desktop.log")
  .normalize()
  .to_string()
}

///|
/// Append a timestamped line to the launch log beside the executable.
pub fn append_launch_log(framework_command : String, message : String) -> Unit {
  let path = launch_log_path(framework_command)
  let previous = if @mbfs.path_exists(path) {
    @mbfs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  let line = @env.now().to_string() + " " + message + "\n"
  ignore(@mbfs.write_string_to_file(path, previous + line) catch { _ => () })
}
