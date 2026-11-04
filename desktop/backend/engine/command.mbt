///|
const DefaultEngine = "openseek"

///|
#cfg(platform="windows")
const PackagedEnginePath = "seekmoon/bin/openseek.exe"

///|
#cfg(not(platform="windows"))
const PackagedEnginePath = "seekmoon/bin/openseek"

///|
async test "development engine falls back to PATH when the Moon output is absent" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-missing-engine-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  assert_eq(engine_command({ dir: resources, packaged: false, }), DefaultEngine)
}
