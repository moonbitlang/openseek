///|
async test "upload timeouts are actionable and external cancellation propagates" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let snapshot = Snapshot(title="Test", html="<html/>", json="{}")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      // The accept loop owns the listener: closing it here, when the group
      // cancels this task, is what lets the loop terminate.
      defer server.close()
      for ;; {
        let (connection, _) = server.accept()
        group.spawn_bg(no_wait=true, () => {
          defer connection.close()
          ignore(connection.read_request())
          connection.skip_request_body()
          @async.sleep(60_000)
        })
      }
    })
    let reply = snapshot.publish(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="test-token",
      timeout_ms=100,
    )
    guard reply is Failed(message~) else { fail("expected upload timeout") }
    assert_true(message.contains("timed out"))
    let cancelled = @async.with_timeout_opt(100, () => {
      snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test-token",
      )
    })
    assert_true(cancelled is None)
  })
}

///|
test "long metadata titles are bounded on character boundaries without truncating conversation files" {
  for
    (title, expected) in [
      ("a".repeat(341), "a".repeat(341)),
      ("a".repeat(1025), "a".repeat(341)),
      ("中".repeat(342), "中".repeat(341)),
      ("😀".repeat(257), "😀".repeat(170)),
      ("a".repeat(340) + "😀", "a".repeat(340)),
    ] {
    let snapshot = Snapshot(
      title~,
      html="<html>\{title}</html>",
      json="{\"prompt\":\"\{title}\"}",
    )
    let body = @utf8.decode(snapshot.body)
    assert_true(body.contains("name=\"title\"\r\n\r\n\{expected}\r\n"))
    assert_true(@utf8.encode(expected).length() <= 1024)
    assert_true(body.contains("<html>\{title}</html>"))
    assert_true(body.contains("{\"prompt\":\"\{title}\"}"))
  }
}
