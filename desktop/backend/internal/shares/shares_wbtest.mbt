///|
async test "upload timeouts are actionable and external cancellation propagates" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let snapshot = Snapshot(title="Test", html="<html/>", json="{}")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
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
    let reply = snapshot.publish_with_timeout(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="test-token",
      timeout_ms=100,
    )
    guard reply is Failed(message~) else { fail("expected upload timeout") }
    assert_true(message.contains("timed out"))
    assert_false(message.contains("may already have been created"))
    let cancelled = @async.with_timeout_opt(100, () => {
      snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test-token",
      )
    })
    assert_true(cancelled is None)
  })
}
