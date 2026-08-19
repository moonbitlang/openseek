///|
const DefaultEngine = "openseek"

///|
async fn local_engine_path(framework_command : String) -> String? {
  let command_path : @pathx.Path = framework_command
  let command_dir = command_path.dirname().resolve()
  let candidates = match @env.get("OS") {
    Some("Windows_NT") => ["openseek.exe", "openseek"]
    _ => ["openseek", "openseek.exe"]
  }
  // Proton preserves bundle.resources below Contents/Resources. Probe that
  // packaged layout before the executable-adjacent layout used on Windows and
  // Linux.
  for candidate in candidates {
    let path = command_dir
      .join("..")
      .join("Resources")
      .join("target/proton-package-input/bin")
      .join(candidate)
      .normalize()
      .to_string()
    if @fs.exists(path) {
      return Some(path)
    }
  }
  for candidate in candidates {
    let path = command_dir.join(candidate).normalize().to_string()
    if @fs.exists(path) {
      return Some(path)
    }
  }
  // An unbundled `moon run ./desktop/package/dev` host and its engine belong to
  // one validated Moon development layout and native profile.
  if @development.Layout::detect(framework_command) is Some(layout) {
    let engine_dir : @pathx.Path = layout.engine_dir()
    for candidate in candidates {
      let path = engine_dir.join(candidate).normalize().to_string()
      if @fs.exists(path) {
        return Some(path)
      }
    }
  }
  None
}

///|
/// The engine executable to run: the packaged engine, then the engine from the
/// host's matching Moon build directory, and finally `openseek` on PATH for
/// other unbundled layouts.
pub async fn engine_command(framework_command : String) -> String {
  if local_engine_path(framework_command) is Some(path) {
    return path
  }
  DefaultEngine
}
