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
/// below Proton's resource directory. The supported development launcher
/// declares `desktop/` as that directory and always builds the native debug
/// host and engine together, so no executable path needs to cross this API.
pub async fn engine_command() -> String {
  let resource_dir : @pathx.Path = @proton.resource_dir()
  if @proton.is_packaged() {
    return resource_dir.join(PackagedEnginePath).normalize().to_string()
  }
  let engine_dir = resource_dir
    .dirname()
    .join("_build/native/debug/build/bobzhang/openseek/cmd/openseek")
  for candidate in ["openseek.exe", "openseek"] {
    let path = engine_dir.join(candidate).normalize().to_string()
    if @fs.exists(path) {
      return path
    }
  }
  DefaultEngine
}

///|
async test "development layout cannot be shadowed by packaged resources" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let build = root.join("_build/native/debug/build")
  let engine_dir = build.join("bobzhang/openseek/cmd/openseek")
  let development = engine_dir.join("openseek.exe").to_string()
  @fs.mkdir(engine_dir.to_string(), recursive=true)
  @fs.write_file(development, "development", create_mode=CreateOrTruncate)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  let resource_dir = resources.to_string()
  let previous_resource_dir = @sys.get_env_var("PROTON_RESOURCE_DIR")
  defer (match previous_resource_dir {
    Some(value) => @sys.set_env_var("PROTON_RESOURCE_DIR", value)
    None => @sys.unset_env_var("PROTON_RESOURCE_DIR")
  })
  @sys.set_env_var("PROTON_RESOURCE_DIR", resource_dir)
  assert_eq(engine_command(), development)
}

///|
async test "development engine falls back to PATH when the Moon output is absent" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-missing-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  let resource_dir = resources.to_string()
  let previous_resource_dir = @sys.get_env_var("PROTON_RESOURCE_DIR")
  defer (match previous_resource_dir {
    Some(value) => @sys.set_env_var("PROTON_RESOURCE_DIR", value)
    None => @sys.unset_env_var("PROTON_RESOURCE_DIR")
  })
  @sys.set_env_var("PROTON_RESOURCE_DIR", resource_dir)
  assert_eq(engine_command(), DefaultEngine)
}
