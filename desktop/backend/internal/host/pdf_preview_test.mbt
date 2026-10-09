///|
async test "local PDF preview returns an absolute path and preserves refusals" {
  let dir = @fs.tmpdir(prefix="openseek-host-pdf-")
  defer @fs.rmdir(dir, recursive=true)
  let file = "\{dir}/中文 #100%.pdf"
  @fs.write_file(file, "%PDF-1.7\n%%EOF\n", create_mode=CreateOrTruncate)
  let reply = @host.open_path_preview({
    session: "pdf-test",
    cwd: None,
    path: file,
  })
  guard @pathx.Path(file).to_absolute() is Some(absolute) &&
    absolute.to_uri_path() is Some(path) else {
    fail("expected absolute temp path")
  }
  assert_true(reply is Pdf(actual) && actual == path)
  @fs.remove(file)
  assert_true(
    @host.open_path_preview({ session: "pdf-test", cwd: None, path: file, })
    is Refused(_),
  )
}
