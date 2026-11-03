///|
async test "local console opens pages and command sockets without credentials" {
  let root = @fs.tmpdir(prefix="openseek-console-direct-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file("\{root}/index.html", "<h1>Local console</h1>")
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    assert_eq(console.entry_url(), origin + "/device/host/chat")
    for query in ["", "?device=host&workspace=%2Ftmp"] {
      let (response, _) = @http.get(origin + "/" + query)
      assert_eq(response.code, 302)
      assert_eq(
        response.headers.get("Location"),
        Some("/device/host/chat" + query),
      )
      assert_eq(response.headers.get("Set-Cookie"), None)
    }
    // Each request is a fresh client: direct navigation and reload require
    // no prior visit to a special entry URL or retained browser state.
    for
      path in [
        "/device/host/chat", "/device/host/chat/new", "/device/host/settings",
      ] {
      let (response, body) = @http.get(origin + path)
      assert_eq(response.code, 200)
      assert_eq(body.text(), "<h1>Local console</h1>")
      assert_eq(response.headers.get("Set-Cookie"), None)
    }
    let (me, body) = @http.get(origin + "/v1/auth/me")
    assert_eq(me.code, 200)
    assert_true(@json.parse(body.text()) is { "login": "local", .. })
    let (devices, body) = @http.get(origin + "/v1/devices", headers={
      "Origin": origin,
    })
    assert_eq(devices.code, 200)
    assert_true(
      @json.parse(body.text())
      is { "devices": [{ "id": "host", "online": true, .. }], .. },
    )
    let (logout, _) = @http.post(origin + "/v1/auth/logout", "", headers={
      "Origin": origin,
    })
    assert_eq(logout.code, 204)
    let (me, _) = @http.get(origin + "/v1/auth/me", headers={
      "Cookie": "seekmoon_session=expired",
    })
    assert_eq(me.code, 200)
    guard origin.strip_prefix("http://") is Some(authority) else {
      fail("expected a loopback HTTP origin")
    }
    @async.with_timeout(5000, () => {
      let ws = @websocket.connect("ws://\{authority}/v1/devices/host/ws", headers={
        "Origin": origin,
      })
      defer ws.close()
      assert_true(
        @json.parse(ws.recv().read_all().text())
        is { "method": "agent.connected", .. },
      )
      ws.send_text(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"app.info\",\"params\":{}}",
      )
      assert_true(
        @json.parse(ws.recv().read_all().text())
        is { "id": 1, "result": { "version": String(_), .. }, .. },
      )
    })
  })
}

///|
async test "local console rejects unrelated web origins and hostnames" {
  let root = @fs.tmpdir(prefix="openseek-console-origin-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file("\{root}/index.html", "<h1>Local console</h1>")
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    for
      path in [
        "/", "/device/host/chat", "/v1/auth/me", "/v1/devices", "/v1/devices/host/ws",
      ] {
      for foreign in ["https://example.com", "http://127.0.0.1:1", "null"] {
        let (response, _) = @http.get(origin + path, headers={
          "Origin": foreign,
        })
        assert_eq(response.code, 403)
      }
      let client = @http.Client(origin)
      defer client.close()
      let response = client.get(path, extra_headers={
        "Host": "rebound.example",
      })
      assert_eq(response.code, 403)
    }
    let (response, _) = @http.post(origin + "/v1/auth/logout", "", headers={
      "Origin": "https://example.com",
    })
    assert_eq(response.code, 403)
  })
}

///|
async test "local login returns canonical shared routes for this device only" {
  let root = @fs.tmpdir(prefix="openseek-console-login-")
  defer @fs.rmdir(root, recursive=true)
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    for
      (destination, expected) in [
        ("/device/host/settings", "/device/host/settings"),
        ("/device/%68ost/%73kills", "/device/host/skills"),
        (
          "/device/host/skills/market/acme%2ftool%401.0", "/device/host/skills/market/acme%2Ftool%401.0",
        ),
        (
          "/device/host/chat/session/not-loaded", "/device/host/chat/session/not-loaded",
        ),
        (
          "/device/host/chat/new?workspace=%2Fwork%2Bspace", "/device/host/chat/new?workspace=%2Fwork%2Bspace",
        ),
        ("/device/other/skills", "/device/host/chat"),
        ("https://example.com/device/host/skills", "/device/host/chat"),
        ("//example.com/device/host/skills", "/device/host/chat"),
        ("/device/host/not-a-page", "/device/host/chat"),
        ("/device/host/chat/session/%2e%2e", "/device/host/chat"),
        ("/device/host/chat/session/a\\b", "/device/host/chat"),
        ("/device/host/chat/session/%GG", "/device/host/chat"),
        ("/device/host/chat/session/%00", "/device/host/chat"),
        ("/device/host/chat/session/a\r\nb", "/device/host/chat"),
      ] {
      let (response, _) = @http.get(
        origin +
        "/v1/auth/login?return_to=" +
        @uri.encode_component(destination),
      )
      assert_eq(response.code, 302)
      assert_eq(response.headers.get("Location"), Some(expected))
      assert_eq(response.headers.get("Set-Cookie"), None)
    }
    let (missing, _) = @http.get(origin + "/v1/auth/login")
    assert_eq(missing.headers.get("Location"), Some("/device/host/chat"))
    let (invalid_header, _) = @http.get(
      origin +
      "/v1/auth/login?return_to=" +
      @uri.encode_component("/device/host/settings?x=\r\nInjected: yes"),
    )
    assert_eq(invalid_header.code, 400)
    assert_eq(invalid_header.headers.get("Location"), None)
    // Local access is always available, including after a login redirect.
    let (response, _) = @http.get(origin + "/v1/auth/me")
    assert_eq(response.code, 200)
  })
}
