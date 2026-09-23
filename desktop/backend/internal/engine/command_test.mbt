///|
async test "development layout cannot be shadowed by packaged resources" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let build = root.join("_build/native/debug/build")
  let engine_dir = build.join("moonbitlang/openseek")
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
  assert_eq(@engine.engine_command(), development)
}
