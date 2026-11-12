///|
async test "a skill's moonx comes from an absolute PATH directory only" {
  let dir = @fs.tmpdir(prefix="openseek-moonx-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.mkdir("\{dir}/bin", recursive=true)
  @fs.write_text("\{dir}/bin/\{ProgramFile}", "", create_mode=CreateOrTruncate)
  // The current directory and relative entries never supply it.
  let path = [".", "", "bin", "\{dir}/missing", "\{dir}/bin"].join(
    PathListSeparator,
  )
  assert_eq(trusted_moonx(path), Some("\{dir}/bin/\{ProgramFile}"))
  assert_eq(trusted_moonx(["bin", "."].join(PathListSeparator)), None)
}
