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
    // Redirecting is not authentication; login must not mint a session.
    let (unauthenticated, _) = @http.get(origin + "/v1/auth/me")
    assert_eq(unauthenticated.code, 401)
  })
}

///|
async test "local account handoff requires the launch session and rereads the Desktop account" {
  let root = @fs.tmpdir(prefix="openseek-console-account-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/index.html",
    "<!doctype html><html><head></head><body>Local console fixture</body></html>",
  )
  let account : @protocol.AccountSession = {
    token: "ts_local_console_fixture",
    user: { user_id: "local-fixture", login: "fixture-user", avatar_url: "", },
  }
  let persisted : Json = {
    "version": 2,
    "server_url": @auth.AccountOrigin,
    "account": account.to_json(),
  }
  @fs.write_file(root + "/auth.json", persisted.stringify(), permission=0o600)
  let store = @auth.AuthStore::load(runtime_dir=Path(root))
  assert_true(store.account() == Some(account))
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(
    engine="unused-test-engine",
    runtime_dir=Path(root),
    auth=store,
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    let endpoint = origin + "/v1/auth/session"
    let (unauthorized, body) = @http.get(endpoint)
    assert_eq(unauthorized.code, 401)
    assert_false(body.text().contains(account.token))
    let (entry, document) = @http.get(console.entry_url())
    assert_eq(entry.code, 200)
    assert_true(
      document.text().contains("<meta name=\"seekmoon-local-console\" />"),
    )
    assert_false(document.text().contains(account.token))
    for path in ["/cloud", "/index.html"] {
      let (response, body) = @http.get(origin + path)
      assert_eq(response.code, 200)
      assert_true(
        body.text().contains("<meta name=\"seekmoon-local-console\" />"),
      )
      assert_false(body.text().contains(account.token))
    }
    guard entry.cookies is [launch_cookie] else {
      fail("local launch did not grant its cookie")
    }
    let cookie = "\{launch_cookie.name}=\{launch_cookie.value}"
    let denied : Array[Map[@http.CaseInsensitiveString, String]] = [
      { "Origin": origin },
      { "Cookie": "\{launch_cookie.name}=wrong", "Origin": origin },
      { "Cookie": cookie, "Origin": "https://other.example" },
    ]
    for headers in denied {
      let (response, body) = @http.get(endpoint, headers~)
      assert_eq(response.code, 401)
      assert_false(body.text().contains(account.token))
    }
    let headers : Map[@http.CaseInsensitiveString, String] = {
      "Cookie": cookie,
      "Origin": origin,
    }
    let (authorized, body) = @http.get(endpoint, headers~)
    assert_eq(authorized.code, 200)
    assert_eq(authorized.headers.get("Cache-Control"), Some("no-store"))
    assert_eq(authorized.headers.get("Set-Cookie"), None)
    assert_eq(authorized.cookies.length(), 0)
    let reply : @protocol.AccountSessionReply = @json.from_json(body.json())
    assert_true(reply.session == Some(account))
    // Expiring the shared native account must affect the very next read;
    // the local launch authorization remains independent of that account.
    store.expire_account(account.token)
    let (signed_out, body) = @http.get(endpoint, headers~)
    assert_eq(signed_out.code, 200)
    let reply : @protocol.AccountSessionReply = @json.from_json(body.json())
    assert_true(reply.session is None)
    assert_eq(body.text(), "{}")
    assert_false(body.text().contains(account.token))
    let (roster, _) = @http.get(origin + "/v1/devices", headers~)
    assert_eq(roster.code, 200)
  })
}

///|
async test "local console documents identify their server without exposing account credentials" {
  let root = @fs.tmpdir(prefix="openseek-console-marker-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/index.html",
    "<!doctype html><html><head></head><body>Local console fixture</body></html>",
  )
  let binary = b"\xff\x00\x80"
  @fs.write_file(root + "/asset.bin", binary)
  let console = @remote.LocalConsole::bind(port=0)
  let state = @api.ApiState(engine="unused-test-engine", runtime_dir=Path(root))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    let origin = console.origin()
    for path in ["/cloud", "/device/host/chat", "/index.html"] {
      let (response, body) = @http.get(origin + path)
      assert_eq(response.code, 200)
      assert_true(
        body.text().contains("<meta name=\"seekmoon-local-console\" />"),
      )
      assert_eq(response.headers.get("Set-Cookie"), None)
      assert_eq(response.cookies.length(), 0)
    }
    let (asset, body) = @http.get(origin + "/asset.bin")
    assert_eq(asset.code, 200)
    assert_eq(body.binary(), binary)
    let (unauthorized, _) = @http.get(origin + "/v1/auth/session")
    assert_eq(unauthorized.code, 401)
  })
}
