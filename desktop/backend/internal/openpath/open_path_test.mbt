// Black-box filesystem tests for the public editor/system routing contract.

///|
async test "existing files win before editor positions" {
  // `tmpdir` is unique even when Moon runs packages concurrently, unlike a
  // shared `_build` parent that several tests may try to create at once.
  let dir = @fs.tmpdir(prefix="openseek-openpath-resolution-")
  let base = "\{dir}/source.mbt"
  let literal = "\{base}:2738"
  @fs.write_file(base, "base", create_mode=CreateOrTruncate)
  @fs.write_file(literal, "literal", create_mode=CreateOrTruncate)
  @debug.assert_eq(
    @openpath.Reference(base).resolve(),
    EditorPath(path=base, line=None, column=None),
  )
  @debug.assert_eq(
    @openpath.Reference(literal).resolve(),
    EditorPath(path=literal, line=None, column=None),
  )
  @fs.remove(literal)
  @debug.assert_eq(
    @openpath.Reference(literal).resolve(),
    EditorPath(path=base, line=Some(2738), column=None),
  )
  @debug.assert_eq(
    @openpath.Reference("\{base}:2738:17").resolve(),
    EditorPath(path=base, line=Some(2738), column=Some(17)),
  )
  let fragment = "\{base}#L5"
  @fs.write_file(fragment, "literal fragment", create_mode=CreateOrTruncate)
  @debug.assert_eq(
    @openpath.Reference(fragment).resolve(),
    EditorPath(path=fragment, line=None, column=None),
  )
  @fs.remove(fragment)
  @debug.assert_eq(
    @openpath.Reference(fragment).resolve(),
    EditorPath(path=base, line=Some(5), column=None),
  )
  @debug.assert_eq(
    @openpath.Reference("\{dir}/missing.mbt:12").resolve(),
    MissingPath("\{dir}/missing.mbt"),
  )
  @debug.assert_eq(
    @openpath.Reference("\{dir}/missing.mbt:12:4").resolve(),
    MissingPath("\{dir}/missing.mbt"),
  )
  let literal_missing = [
    "\{dir}/missing.mbt:0",
    "\{dir}/missing.mbt:not-a-line",
    "\{dir}/missing.mbt#L0",
    "\{dir}/ordinary.mbt",
  ]
  for path in literal_missing {
    @debug.assert_eq(@openpath.Reference(path).resolve(), MissingPath(path))
  }
  @debug.assert_eq(@openpath.Reference("\{dir}:12").resolve(), SystemPath(dir))
  // Content routing follows the built-in viewer's UTF-8 and size policy.
  let binary = "\{dir}/image.bin"
  @fs.write_file(binary, b"\xff\xd8\xff\x00", create_mode=CreateOrTruncate)
  @debug.assert_eq(
    @openpath.Reference(binary).resolve(),
    EditorPath(path=binary, line=None, column=None),
  )
  let pdf = "\{dir}/document.pdf"
  @fs.write_file(pdf, "%PDF-1.7\n%%EOF\n", create_mode=CreateOrTruncate)
  @debug.assert_eq(@openpath.Reference(pdf).resolve(), BrowserPath(pdf))
  let oversized = "\{dir}/large.txt"
  let content = "x".repeat(@openpath.MaxEditorFileBytes + 1)
  @fs.write_file(oversized, content, create_mode=CreateOrTruncate)
  @debug.assert_eq(
    @openpath.Reference(oversized).resolve(),
    SystemPath(oversized),
  )
}

///|
async test "PDF content is recognized before the text size limit" {
  let dir = @fs.tmpdir(prefix="openseek-openpath-pdf-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/中文 #100%"
  @fs.write_file(
    path,
    "%PDF-1.7\n" + "x".repeat(@openpath.MaxEditorFileBytes + 1),
    create_mode=CreateOrTruncate,
  )
  assert_true(
    @openpath.Reference(path).resolve() is BrowserPath(actual) && actual == path,
  )
  @fs.write_file(path, "ordinary text", create_mode=TruncateExisting)
  assert_true(@openpath.Reference(path).resolve() is EditorPath(..))
  @fs.write_file(path, "", create_mode=TruncateExisting)
  assert_true(@openpath.Reference(path).resolve() is EditorPath(..))
}
