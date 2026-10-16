///|
async test "remote registration uses the account, and disabling preserves it" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  let store = AuthStore::empty()
  store.session = Some({
    ..sample_session(avatar=""),
    server_url: origin,
    device: None,
  })
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      for step in 0..<2 {
        let (conn, _) = server.accept()
        defer conn.close()
        let request = conn.read_request()
        conn.skip_request_body()
        if step == 0 {
          assert_true(request.meth is Post)
          assert_eq(request.path, "/v2/devices")
          assert_eq(
            request.headers.get("Authorization"),
            Some("Bearer ts_secret"),
          )
          conn.send_response(201, "Created")
          conn.write_string(
            "{\"device_token\":\"odt_new\",\"device\":{\"id\":\"d_new\",\"name\":\"Test\"}}",
          )
        } else {
          assert_true(request.meth is Delete)
          assert_eq(request.path, "/v2/devices/d_new")
          assert_eq(
            request.headers.get("Authorization"),
            Some("Bearer odt_new"),
          )
          conn.send_response(204, "No Content")
        }
        conn.end_response()
      }
    })
    store.set_remote(true)
    assert_true(
      store.desired_connector() is Some({ device_token: "odt_new", .. }),
    )
    store.set_remote(false)
    assert_true(store.account() is Some({ token: "ts_secret", .. }))
    assert_true(store.desired_connector() is None)
    receiver.wait()
  })
}

///|
async test "cancelled registration reads its device credential and revokes it" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let origin = "http://127.0.0.1:\{server.addr.port()}"
    let store = AuthStore::empty()
    store.session = Some({
      ..sample_session(avatar=""),
      server_url: origin,
      device: None,
    })
    @async.with_task_group(group => {
      let operation = group.spawn(() => store.set_remote(true))
      let (conn, _) = server.accept()
      defer conn.close()
      assert_eq(conn.read_request().path, "/v2/devices")
      conn.skip_request_body()
      operation.cancel()
      conn.send_response(201, "Created")
      conn.write_string(
        "{\"device_token\":\"odt_cancelled\",\"device\":{\"id\":\"d_cancelled\",\"name\":\"Test\"}}",
      )
      conn.end_response()
      let (cleanup, _) = server.accept()
      defer cleanup.close()
      let request = cleanup.read_request()
      assert_true(request.meth is Delete)
      assert_eq(request.path, "/v2/devices/d_cancelled")
      assert_eq(
        request.headers.get("Authorization"),
        Some("Bearer odt_cancelled"),
      )
      cleanup.skip_request_body()
      cleanup.send_response(204, "No Content")
      cleanup.end_response()
      @async.handle_cancellation(() => operation.wait()) |> ignore
      assert_true(store.account() is Some({ token: "ts_secret", .. }))
      assert_true(store.desired_connector() is None)
    })
  })
}

///|
async test "disable and sign-out retire the device committed while waiting for persistence" {
  for sign_out in [false, true] {
    @async.with_timeout(5000, () => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let session = {
        ..sample_session(avatar=""),
        server_url: "http://127.0.0.1:\{server.addr.port()}",
        device: None,
      }
      let store = AuthStore::empty()
      store.session = Some(session)
      @async.with_task_group(group => {
        store.persist_mutex.acquire()
        let logout = group.spawn(() => {
          if sign_out {
            store.sign_out()
          } else {
            store.set_remote(false)
          }
        })
        @async.sleep(0)
        // Finish the earlier writer while holding the same persistence lock.
        store.session = Some({
          ..session,
          device: Some({
            token: "odt_just_committed",
            id: "d_just_committed",
            name: "Test",
          }),
        })
        store.persist_mutex.release()
        let paths = if sign_out {
          ["/v2/devices/d_just_committed", "/v2/auth/logout"]
        } else {
          ["/v2/devices/d_just_committed"]
        }
        for path in paths {
          let (conn, _) = server.accept()
          defer conn.close()
          let request = conn.read_request()
          assert_eq(request.path, path)
          conn.skip_request_body()
          conn.send_response(204, "No Content")
          conn.end_response()
        }
        logout.wait()
        assert_true(store.signed_in() == !sign_out)
        assert_true(store.desired_connector() is None)
      })
    })
  }
}
