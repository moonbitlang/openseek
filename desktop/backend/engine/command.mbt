///|
const DefaultEngine = "openseek"

///|
#cfg(platform="windows")
const PackagedEnginePath = "seekmoon/bin/openseek.exe"

///|
#cfg(not(platform="windows"))
const PackagedEnginePath = "seekmoon/bin/openseek"

///|
/// The engine executable to run. Installed apps use canonical `seekmoon/`
/// below the resource directory. The supported development launcher
/// declares `desktop/` as that directory and always builds the native debug
/// host and engine together, so no executable path needs to cross this API.
pub async fn engine_command(resources : @resources.Resources) -> String {
  if resources.packaged {
    return resources.dir.join(PackagedEnginePath).normalize().to_string()
  }
  let engine_dir = resources.dir
    .dirname()
    .join("_build/native/debug/build/moonbitlang/openseek")
  for candidate in ["openseek.exe", "openseek"] {
    let path = engine_dir.join(candidate).normalize().to_string()
    if @fs.exists(path) {
      return path
    }
  }
  DefaultEngine
}

///|
async test "development engine falls back to PATH when the Moon output is absent" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-missing-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  assert_eq(engine_command({ dir: resources, packaged: false, }), DefaultEngine)
}
