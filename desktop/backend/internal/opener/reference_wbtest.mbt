// Filesystem tests for the editor/system routing contract.

///|
async test "existing files win before editor positions" {
  // `tmpdir` is unique even when Moon runs packages concurrently, unlike a
  // shared `_build` parent that several tests may try to create at once.
  let dir = @fs.tmpdir(prefix="openseek-opener-resolution-")
  let base = "\{dir}/source.mbt"
  let literal = "\{base}:2738"
  @fs.write_file(base, "base", create_mode=CreateOrTruncate)
  @fs.write_file(literal, "literal", create_mode=CreateOrTruncate)
  assert_true(
    Reference(base).resolve() is EditorPath(path=actual, line=None, column=None) &&
    actual == base,
  )
  assert_true(
    Reference(literal).resolve()
    is EditorPath(path=actual, line=None, column=None) &&
    actual == literal,
  )
  @fs.remove(literal)
  assert_true(
    Reference(literal).resolve()
    is EditorPath(path=actual, line=Some(2738), column=None) &&
    actual == base,
  )
  assert_true(
    Reference("\{base}:2738:17").resolve()
    is EditorPath(path=actual, line=Some(2738), column=Some(17)) &&
    actual == base,
  )
  let fragment = "\{base}#L5"
  @fs.write_file(fragment, "literal fragment", create_mode=CreateOrTruncate)
  assert_true(
    Reference(fragment).resolve()
    is EditorPath(path=actual, line=None, column=None) &&
    actual == fragment,
  )
  @fs.remove(fragment)
  assert_true(
    Reference(fragment).resolve()
    is EditorPath(path=actual, line=Some(5), column=None) &&
    actual == base,
  )
  assert_true(
    Reference("\{dir}/missing.mbt:12").resolve() is MissingPath(actual) &&
    actual == "\{dir}/missing.mbt",
  )
  assert_true(
    Reference("\{dir}/missing.mbt:12:4").resolve() is MissingPath(actual) &&
    actual == "\{dir}/missing.mbt",
  )
  let literal_missing = [
    "\{dir}/missing.mbt:0",
    "\{dir}/missing.mbt:not-a-line",
    "\{dir}/missing.mbt#L0",
    "\{dir}/ordinary.mbt",
  ]
  for path in literal_missing {
    assert_true(
      Reference(path).resolve() is MissingPath(actual) && actual == path,
    )
  }
  assert_true(
    Reference("\{dir}:12").resolve() is SystemPath(actual) && actual == dir,
  )
  // Content routing follows the built-in viewer's UTF-8 and size policy.
  let binary = "\{dir}/image.bin"
  @fs.write_file(binary, b"\xff\xd8\xff\x00", create_mode=CreateOrTruncate)
  assert_true(
    Reference(binary).resolve() is BrowserPath(actual) && actual == binary,
  )
  let pdf = "\{dir}/document.pdf"
  @fs.write_file(pdf, "%PDF-1.7\n%%EOF\n", create_mode=CreateOrTruncate)
  assert_true(
    Reference(pdf).resolve() is EditorPath(path=actual, line=None, column=None) &&
    actual == pdf,
  )
  for name in ["document.docx", "slides.PPTX"] {
    let office = "\{dir}/\{name}"
    @fs.write_file(office, b"PK\x03\x04office", create_mode=CreateOrTruncate)
    assert_true(
      Reference(office).resolve()
      is EditorPath(path=actual, line=None, column=None) &&
      actual == office,
    )
  }
  let oversized_office = "\{dir}/large.xlsx"
  @fs.write_file(
    oversized_office,
    "x".repeat(@files.MaxOfficeFileBytes + 1),
    create_mode=CreateOrTruncate,
  )
  assert_true(
    Reference(oversized_office).resolve() is SystemPath(actual) &&
    actual == oversized_office,
  )
  let oversized = "\{dir}/large.txt"
  let content = "x".repeat(@files.MaxEditorFileBytes + 1)
  @fs.write_file(oversized, content, create_mode=CreateOrTruncate)
  assert_true(
    Reference(oversized).resolve() is SystemPath(actual) && actual == oversized,
  )
}

///|
async test "PDF content is recognized before the text size limit" {
  let dir = @fs.tmpdir(prefix="openseek-opener-pdf-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/中文 #100%"
  @fs.write_file(
    path,
    "%PDF-1.7\n" + "x".repeat(@files.MaxEditorFileBytes + 1),
    create_mode=CreateOrTruncate,
  )
  assert_true(
    Reference(path).resolve() is EditorPath(path=actual, ..) && actual == path,
  )
  @fs.write_file(
    path,
    "%PDF-1.7\n" + "x".repeat(@files.MaxOfficeFileBytes),
    create_mode=TruncateExisting,
  )
  assert_true(Reference(path).resolve() is SystemPath(actual) && actual == path)
  @fs.write_file(path, "ordinary text", create_mode=TruncateExisting)
  assert_true(Reference(path).resolve() is EditorPath(..))
  @fs.write_file(path, "", create_mode=TruncateExisting)
  assert_true(Reference(path).resolve() is EditorPath(..))
}

///|
async test "raster images use browser routing regardless of name and text size limit" {
  let dir = @fs.tmpdir(prefix="openseek-opener-images-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/image.txt"
  for
    header in [
      b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF87a", b"GIF89a", b"RIFF\x00\x00\x00\x00WEBP",
    ] {
    @fs.write_file(path, header, create_mode=CreateOrTruncate)
    assert_true(
      Reference(path).resolve() is BrowserPath(actual) && actual == path,
    )
  }
  @fs.write_file(
    path,
    "GIF89a" + "x".repeat(@files.MaxEditorFileBytes + 1),
    create_mode=TruncateExisting,
  )
  assert_true(
    Reference(path).resolve() is BrowserPath(actual) && actual == path,
  )
  @fs.write_file(path, b"\x00unsupported binary", create_mode=TruncateExisting)
  assert_true(Reference(path).resolve() is SystemPath(actual) && actual == path)
}
