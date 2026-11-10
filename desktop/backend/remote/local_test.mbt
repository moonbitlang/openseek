///|
async test "local console access does not require credentials" {
  let root = @fs.tmpdir(prefix="openseek-console-direct-")
  defer @fs.rmdir(root, recursive=true)
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    assert_eq(console.entry_url(), origin + "/device/host/chat")
    for query in ["", "?device=host&workspace=%2Ftmp"] {
      let (response, _) = @http.get_text(origin + "/" + query)
      assert_eq(response.code, 302)
      assert_eq(
        response.headers.get("Location"),
        Some("/device/host/chat" + query),
      )
      assert_eq(response.headers.get("Set-Cookie"), None)
    }
    let (me, body) = @http.get_text(origin + "/v1/auth/me")
    assert_eq(me.code, 200)
    assert_true(@json.parse(body) is { "login": "local", .. })
    let (devices, body) = @http.get_text(origin + "/v1/devices", headers={
      "Origin": origin,
    })
    assert_eq(devices.code, 200)
    assert_true(
      @json.parse(body)
      is { "devices": [{ "id": "host", "online": true, .. }], .. },
    )
    let (logout, _) = @http.post_text(origin + "/v1/auth/logout", "", headers={
      "Origin": origin,
    })
    assert_eq(logout.code, 204)
    let (me, _) = @http.get_text(origin + "/v1/auth/me", headers={
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
        @json.parse(ws.recv().text.read_all())
        is { "method": "agent.connected", .. },
      )
      ws.send_text(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"app.info\",\"params\":{}}",
      )
      assert_true(
        @json.parse(ws.recv().text.read_all())
        is { "id": 1, "result": { "version": String(_), .. }, .. },
      )
    })
  })
}

///|
async test "local console rejects unrelated web origins and hostnames" {
  let root = @fs.tmpdir(prefix="openseek-console-origin-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_text("\{root}/index.html", "<h1>Local console</h1>")
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    guard origin.strip_prefix("http://") is Some(authority) else {
      fail("expected an http origin")
    }
    for
      path in [
        "/", "/device/host/chat", "/v1/auth/me", "/v1/devices", "/v1/devices/host/ws",
        "/v2/auth/login", "/cb",
      ] {
      for foreign in ["https://example.com", "http://127.0.0.1:1", "null"] {
        let (response, _) = @http.get_text(origin + path, headers={
          "Origin": foreign,
        })
        assert_eq(response.code, 403)
      }
      // The HTTP client always sends its own Host, so write this request by hand.
      let socket = @socket.Tcp::connect(@socket.Addr::parse(authority))
      defer socket.close()
      socket.write(
        @utf8.encode(
          "GET \{path} HTTP/1.1\r\nHost: rebound.example\r\nConnection: close\r\n\r\n",
        ),
      )
      guard socket.read_until(b"\r\n") is Some(status) else {
        fail("expected a response")
      }
      assert_true(@utf8.decode(status).has_prefix("HTTP/1.1 403 "))
    }
    let (response, _) = @http.post_text(origin + "/v1/auth/logout", "", headers={
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
        (
          "/device/host/chat/session/not-loaded", "/device/host/chat/session/not-loaded",
        ),
        (
          "/device/host/chat/new?workspace=%2Fwork%2Bspace", "/device/host/chat/new?workspace=%2Fwork%2Bspace",
        ),
        ("/device/other/chat", "/device/host/chat"),
        ("https://example.com/device/host/chat", "/device/host/chat"),
        ("//example.com/device/host/chat", "/device/host/chat"),
        ("/device/host/not-a-page", "/device/host/chat"),
        ("/device/host/chat/session/%2e%2e", "/device/host/chat"),
        ("/device/host/chat/session/a\\b", "/device/host/chat"),
        ("/device/host/chat/session/%GG", "/device/host/chat"),
        ("/device/host/chat/session/%00", "/device/host/chat"),
        ("/device/host/chat/session/a\r\nb", "/device/host/chat"),
      ] {
      let (response, _) = @http.get_text(
        origin +
        "/v1/auth/login?return_to=" +
        @uri.encode_component(destination),
      )
      assert_eq(response.code, 302)
      assert_eq(response.headers.get("Location"), Some(expected))
      assert_eq(response.headers.get("Set-Cookie"), None)
    }
    let (missing, _) = @http.get_text(origin + "/v1/auth/login")
    assert_eq(missing.headers.get("Location"), Some("/device/host/chat"))
    let (invalid_header, _) = @http.get_text(
      origin +
      "/v1/auth/login?return_to=" +
      @uri.encode_component("/device/host/chat?x=\r\nInjected: yes"),
    )
    assert_eq(invalid_header.code, 400)
    assert_eq(invalid_header.headers.get("Location"), None)
    // Local access is always available, including after a login redirect.
    let (response, _) = @http.get_text(origin + "/v1/auth/me")
    assert_eq(response.code, 200)
  })
}

///|
async test "local browser sign-in and logout are independent of Desktop and keep local access" {
  let root = @fs.tmpdir(prefix="openseek-console-account-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_text(root + "/index.html", "<html><head></head></html>")
  let desktop_account : @protocol.AccountSession = {
    token: "ts_desktop-token",
    user: { user_id: "desktop", login: "desktop", avatar_url: "", },
  }
  let persisted : Json = {
    "version": 2,
    "server_url": @auth.AccountOrigin,
    "account": desktop_account.to_json(),
  }
  @fs.write_text(root + "/auth.json", persisted.stringify(), permission=0o600)
  let store = @auth.AuthStore::load(runtime_dir=Path(root))
  assert_true(store.account() == Some(desktop_account))
  let state = @api.ApiState(engine="unused", runtime_dir=Path(root), auth=store)
  let issuer = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer issuer.close()
  let console = @remote.LocalConsole::bind(
    port=0,
    account_origin="http://127.0.0.1:\{issuer.addr.port()}",
  )
  let exchanges : Array[String] = []
  let logouts : Array[String?] = []
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    group.spawn_bg(no_wait=true, () => {
      for ;; {
        let (conn, _) = issuer.accept()
        defer conn.close()
        let request = conn.read_request()
        let body = if request.path == "/v2/auth/account/exchange" {
          guard @json.parse(conn.text.read_all())
            is {
              "code": String("browser-code"),
              "code_verifier": String(verifier),
              ..
            } else {
            fail("expected the browser PKCE exchange")
          }
          exchanges.push(verifier)
          "{\"token\":\"ts_browser-token\",\"user\":{\"user_id\":\"browser\",\"login\":\"browser\",\"avatar_url\":\"\"}}"
        } else {
          assert_eq(request.path, "/v2/auth/logout")
          logouts.push(request.headers.get("authorization"))
          assert_eq(request.headers.get("cookie"), None)
          "{}"
        }
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
          "Content-Length": body.length().to_string(),
          "Connection": "close",
        })
        conn.write_string(body)
        conn.end_response()
      }
    })
    let origin = console.origin()
    let login = origin + "/v2/auth/login?return_to=%2Fcloud"
    let headers : Map[@http.CaseInsensitiveString, String] = {
      "Origin": origin,
    }
    let (foreign, _) = @http.get_text(login, headers={
      "Origin": "https://other.example",
    })
    assert_eq(foreign.code, 403)
    // A fresh browser starts account sign-in without any local credentials.
    let (start, _) = @http.get_text(login)
    assert_eq(start.headers.get("Set-Cookie"), None)
    assert_eq(start.code, 302)
    guard start.headers.get("Location") is Some(location) &&
      location.split_once("?state=") is Some((_, rest)) &&
      rest.split_once("&") is Some((oauth_state, params)) else {
      fail("expected the account-service login URL")
    }
    assert_true(params.contains("code_challenge_method=S256"))
    // State and PKCE authorize this browser account exchange independently
    // of the local host access that is already available.
    let callback = origin + "/cb?code=browser-code&state=\{oauth_state}"
    let (response, body) = @http.get_text(callback)
    assert_eq(response.code, 200)
    assert_eq(response.headers.get("Cache-Control"), Some("no-store"))
    assert_eq(response.cookies.length(), 0)
    assert_true(body.contains("ts_browser-token"))
    assert_false(body.contains(desktop_account.token))
    assert_true(body.contains("location.replace(\"/cloud\")"))
    let (replay, _) = @http.get_text(callback)
    assert_eq(replay.code, 400)
    assert_eq(exchanges.length(), 1)
    let (foreign_logout, _) = @http.post_text(origin + "/v2/auth/logout", "", headers={
      "Origin": "https://other.example",
      "Authorization": "Bearer ts_browser-token",
    })
    assert_eq(foreign_logout.code, 403)
    assert_eq(logouts.length(), 0)
    let (signed_out, _) = @http.post_text(origin + "/v2/auth/logout", "", headers={
      "Origin": origin,
      "Authorization": "Bearer ts_browser-token",
    })
    assert_eq(signed_out.code, 200)
    assert_eq(logouts, [Some("Bearer ts_browser-token")])
    assert_true(store.account() == Some(desktop_account))
    let (roster, _) = @http.get_text(origin + "/v1/devices", headers~)
    assert_eq(roster.code, 200)
    let (removed, body) = @http.get_text(origin + "/v1/auth/session", headers~)
    assert_eq(removed.code, 404)
    assert_false(body.contains(desktop_account.token))
  })
}

///|
async test "local console documents identify their server without exposing account credentials" {
  let root = @fs.tmpdir(prefix="openseek-console-marker-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_text(
    root + "/index.html",
    "<!doctype html><html><head></head><body>Local console fixture</body></html>",
  )
  let binary = b"\xff\x00\x80"
  @fs.write_binary(root + "/asset.bin", binary)
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    for path in ["/cloud", "/device/host/chat", "/index.html"] {
      let (response, body) = @http.get_text(origin + path)
      assert_eq(response.code, 200)
      assert_true(body.contains("<meta name=\"seekmoon-local-console\" />"))
      assert_eq(response.headers.get("Set-Cookie"), None)
      assert_eq(response.cookies.length(), 0)
    }
    let (asset, body) = @http.get_binary(origin + "/asset.bin")
    assert_eq(asset.code, 200)
    assert_eq(body, binary)
    let (login, _) = @http.get_text(origin + "/v2/auth/login")
    assert_eq(login.code, 302)
    assert_eq(login.headers.get("Set-Cookie"), None)
  })
}
