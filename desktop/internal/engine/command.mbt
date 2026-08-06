///|
const DefaultEngine = "openseek"

///|
async fn bundled_engine_path(framework_command : String) -> String? {
  let command_path : @path.Path = framework_command
  let command_dir = command_path.dirname().resolve()
  let candidates = match @env.get("OS") {
    Some("Windows_NT") => ["openseek.exe", "openseek"]
    _ => ["openseek", "openseek.exe"]
  }
  // Proton preserves bundle.resources below Contents/Resources. Probe the
  // prepared package input first, then retain the executable-adjacent layouts
  // used by the other platform packagers and development builds.
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
  None
}

///|
/// The engine executable to run: always the one bundled beside the host
/// binary, falling back to `openseek` on PATH only in unbundled (development)
/// layouts. The ambient environment cannot redirect a packaged app at a
/// different engine.
pub async fn engine_command(framework_command : String) -> String {
  if bundled_engine_path(framework_command) is Some(path) {
    return path
  }
  DefaultEngine
}
