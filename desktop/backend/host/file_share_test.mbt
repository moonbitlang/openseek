///|
async test "file share capture preserves bytes and has no text preview limit" {
  let root = @fs.tmpdir(prefix="seekmoon-file-share-")
  defer @fs.rmdir(root, recursive=true)
  let path = @pathx.Path(root).join("报告.bin").to_string()
  let original = b"\x00\xff\xfe\r\noriginal\x00"
  @fs.write_file(path, original)
  let source : @protocol.ReadFilePayload = {
    root: @pathx.Path(root).to_absolute().unwrap().to_uri_path(),
    path: "报告.bin",
  }
  let (name, captured) = @host.capture_file(source)
  @fs.write_file(path, b"replacement")
  assert_eq(name, "报告.bin")
  assert_eq(captured, original)
  let large = Bytes::make(2 * 1024 * 1024, b'\xff')
  @fs.write_file(path, large)
  let (_, captured) = @host.capture_file(source)
  assert_eq(captured, large)
  for path in [".", "../outside.bin"] {
    try @host.capture_file({ ..source, path, }) catch {
      _ => ()
    } noraise {
      _ => fail("directories and paths outside the workspace cannot be shared")
    }
  }
}
