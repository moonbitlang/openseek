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
    let origin = "http://127.0.0.1:\{console.port()}"
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
