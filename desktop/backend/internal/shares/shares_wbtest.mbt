///|
async test "long metadata titles are bounded on character boundaries without truncating conversation files" {
  for
    (title, expected) in [
      ("a".repeat(341), "a".repeat(341)),
      ("a".repeat(1025), "a".repeat(341)),
      ("中".repeat(342), "中".repeat(341)),
      ("😀".repeat(257), "😀".repeat(170)),
      ("a".repeat(340) + "😀", "a".repeat(340)),
    ] {
    let snapshot = Snapshot(
      key="a".repeat(64),
      title~,
      html="<html>\{title}</html>",
      json="{\"prompt\":\"\{title}\"}",
    )
    let reader = @io.MemoryReader(target => snapshot.write_body(target))
    defer reader.close()
    let body = reader.read_all().text()
    assert_true(body.contains("name=\"title\"\r\n\r\n\{expected}\r\n"))
    assert_true(@utf8.encode(expected).length() <= 1024)
    assert_true(body.contains("<html>\{title}</html>"))
    assert_true(body.contains("{\"prompt\":\"\{title}\"}"))
  }
}

///|
async test "multipart size preflight matches encoded framing at the byte limit" {
  let key = "a".repeat(64)
  let empty = Snapshot(key~, title="Test", html="", json="")
  let reader = @io.MemoryReader(target => empty.write_body(target))
  defer reader.close()
  let overhead = reader.read_all().binary().length()
  // Place a surrogate pair across the 4096-code-unit chunk boundary.
  let html = "a".repeat(4095) +
    "😀" +
    "a".repeat(20 * 1024 * 1024 - overhead - 4095 - 4)
  ignore(Snapshot(key~, title="Test", html~, json=""))
  try Snapshot(key~, title="Test", html=html + "x", json="") catch {
    Oversized => ()
    error => raise error
  } noraise {
    _ => fail("one byte over the encoded limit must be refused")
  }
}
