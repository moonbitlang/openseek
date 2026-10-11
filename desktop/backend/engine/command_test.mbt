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
  assert_eq(
    @engine.engine_command({ dir: resources, packaged: false, }),
    development,
  )
}
