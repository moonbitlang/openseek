///|
/// Keep `ModuleVersion` in step with `version` in the root `moon.mod`, so
/// `openseek --version` always reports the release built from this module.
async test "ModuleVersion matches the root moon.mod version" {
  let prefix = "version = \""
  let versions = @fs.read_text("moon.mod")
    .split("\n")
    .map(line => line.trim())
    .filter_map(line => {
      guard line.has_prefix(prefix) else { return None }
      line[prefix.length():].split("\"").next().map(value => value.to_owned())
    })
    .to_array()
  @debug.assert_eq(versions, [ModuleVersion])
}
