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
  // Proton preserves package.resources below Contents/Resources. Probe that
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

///|
async test "packaged sibling wins before the matching Moon build engine" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let build = root.join("_build/native/debug/build")
  let command_dir = build.join("openseek_desktop")
  let host = command_dir.join("openseek_desktop.exe").to_string()
  let engine_dir = build.join("bobzhang/openseek/cmd/openseek")
  let development = engine_dir.join("openseek.exe").to_string()
  @fs.mkdir(command_dir.to_string(), recursive=true)
  @fs.mkdir(engine_dir.to_string(), recursive=true)
  @fs.write_file(development, "development", create_mode=CreateOrTruncate)
  assert_eq(engine_command(host), development)
  let bundled = command_dir.join("openseek").to_string()
  @fs.write_file(bundled, "bundled", create_mode=CreateOrTruncate)
  assert_eq(engine_command(host), bundled)
}
