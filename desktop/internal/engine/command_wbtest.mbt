///|
async test "packaged sibling wins before the matching Moon build engine" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-engine-")
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
  @fs.rmdir(root.to_string(), recursive=true)
}
