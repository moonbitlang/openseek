///|
/// The login the upload captured, relative to the store when HTTP 401 arrives.
priv enum Login {
  // The persisted login, still connected: the refusal must retire it.
  Current
  // A newer login replaced it during the upload: nothing may be cleared.
  Stale
  // The relay actor already retired it for its own refusal.
  Retired
}

///|
async test "share refusal retires the captured login and preserves a newer one" {
  for login in [Current, Stale, Retired] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let origin = "http://127.0.0.1:\{server.addr.port()}"
    let dir : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-share-auth-"))
    defer @fs.rmdir(dir.to_string(), recursive=true)
    @fs.write_file(
      dir.join("auth.json").to_string(),
      "{\"server_url\":\"\{origin}\",\"device_token\":\"current-token\",\"device\":{\"id\":\"device\",\"name\":\"Test\"},\"user\":{\"login\":\"test\",\"avatar_url\":\"\"}}",
    )
    let store = @auth.AuthStore::load(runtime_dir=dir)
    assert_true(store.signed_in())
    ignore(store.mark_registered("device"))
    guard store.desired_connector() is Some(current) else {
      fail("fixture did not load login")
    }
    let config = match login {
      Stale => { ..current, device_token: "old-token", }
      Current | Retired => current
    }
    let state = @api.ApiState(engine="unused-test-engine", auth=store)
    let notifications = state.subscribe()
    let share = SessionShare::{
      state,
      payload: {
        session: "test",
        workspace: ".",
        title: "Test",
        archived: false,
      },
    }
    let snapshot = @shares.Snapshot(
      title="Test",
      html="<html>test</html>",
      json="{}",
    )
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        assert_eq(
          request.headers.get("Authorization"),
          Some("Bearer \{config.device_token}"),
        )
        connection.skip_request_body()
        if login is Retired {
          store.handle_refusal()
          assert_true(store.desired_connector() is None)
        }
        connection.send_response(401, "Unauthorized")
        connection.write_string("{}")
        connection.end_response()
      })
      let reply = share.upload(snapshot, config)
      receiver.wait()
      if login is Stale {
        assert_true(reply is Failed(..))
        assert_true(store.signed_in())
        assert_true(store.status().connected)
        assert_true(store.desired_connector() == Some(current))
        assert_true(notifications.try_next() is None)
      } else {
        assert_true(reply is SignInRequired)
        // auth.connect checks this flag before starting browser sign-in.
        assert_false(store.signed_in())
        assert_false(store.status().connected)
        assert_true(store.desired_connector() is None)
        assert_true(store.wakeups().try_get() is Some(_))
        assert_true(notifications.try_next() is Some(AuthChanged(_)))
        assert_false(@auth.AuthStore::load(runtime_dir=dir).signed_in())
      }
    })
  }
}
