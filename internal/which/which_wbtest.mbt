///|
async test "find looks in absolute PATH directories only" {
  let dir = @fs.tmpdir(prefix="openseek-which-")
  defer @fs.rmdir(dir, recursive=true)
  let file = "\{dir}/bin/moonx\{ExecutableSuffix}"
  @fs.mkdir("\{dir}/bin", recursive=true)
  @fs.write_text(file, "", create_mode=CreateOrTruncate)
  // The current directory and relative entries never supply it.
  let path = [".", "", "bin", "\{dir}/missing", "\{dir}/bin"].join(
    PathListSeparator,
  )
  assert_eq(find("moonx", path~), Some(file))
  assert_eq(find("moonx", path=["bin", "."].join(PathListSeparator)), None)
}
