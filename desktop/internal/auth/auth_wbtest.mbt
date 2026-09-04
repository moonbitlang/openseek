// The pure pieces (PKCE, callback parsing, URLs, the persisted file's
// codec) and the store's transition dedup — everything the live flow in
// signin.mbt is built from.

///|
test "pkce challenge is the verifier's unpadded base64url sha256" {
  // Cross-checked against RFC 7636 S256 (python:
  // urlsafe_b64encode(sha256(b"test-verifier")).rstrip("=")) — and against
  // the relay's own challenge_s256, which must accept what start_url sends.
  inspect(
    pkce_challenge("test-verifier"),
    content="JBbiqONGWPaAmwXk_8bT6UnlPfrn65D32eZlJS-zGG0",
  )
  inspect(pkce_challenge("test-verifier").length(), content="43")
  // Stable across calls — the exchange must send what start_url promised.
  assert_true(pkce_challenge("v") == pkce_challenge("v"))
}

///|
test "start url carries every parameter, name percent-encoded" {
  inspect(
    start_url(
      server_url="https://relay.example/",
      oauth_state="st123",
      challenge="ch456",
      port=49152,
      name="My Mac (work)",
    ),
    content=(
      #|https://relay.example/v1/auth/desktop/start?state=st123&code_challenge=ch456&code_challenge_method=S256&port=49152&name=My%20Mac%20%28work%29
    ),
  )
}

///|
test "callback parsing: granted, denied, strays" {
  assert_true(
    parse_callback("/cb?code=one-time&state=st", oauth_state="st")
    is Granted("one-time"),
  )
  assert_true(
    parse_callback("/cb?error=access_denied&state=st", oauth_state="st")
    is Denied("access_denied"),
  )
  // Wrong or missing state is a stray, never a denial — a loopback guesser
  // must not be able to end the flow.
  assert_true(
    parse_callback("/cb?code=one-time&state=forged", oauth_state="st") is Stray,
  )
  assert_true(parse_callback("/cb?code=one-time", oauth_state="st") is Stray)
  assert_true(parse_callback("/cb?state=st", oauth_state="st") is Stray)
  assert_true(parse_callback("/favicon.ico", oauth_state="st") is Stray)
  assert_true(
    parse_callback("/cb?code=a%20b&state=st", oauth_state="st")
    is Granted("a b"),
  )
}

///|
test "url derivations" {
  inspect(
    tunnel_url("https://openseek-api.moonbitlang.cn"),
    content="wss://openseek-api.moonbitlang.cn/v1/tunnel",
  )
  inspect(
    tunnel_url("http://127.0.0.1:3000/"),
    content="ws://127.0.0.1:3000/v1/tunnel",
  )
  inspect(
    device_url("https://relay.example", "d_abc", app_version="0.1.16"),
    content="https://relay.example/console/releases/v0.1.16/index.html?device=d_abc",
  )
  inspect(
    device_url("https://relay.example/", "d_abc", app_version="development"),
    content="https://relay.example/console/?device=d_abc",
  )
  inspect(
    origin_from_relay_url("wss://relay.example/v1/tunnel"),
    content="https://relay.example",
  )
  inspect(
    origin_from_relay_url("ws://127.0.0.1:8080/v1/tunnel"),
    content="http://127.0.0.1:8080",
  )
}

///|
test "auth.json codec round-trips and reads corruption as signed out" {
  let session : AuthSession = {
    server_url: "https://relay.example",
    device_token: "odt_secret",
    device_id: "d_abc",
    device_name: "My Mac",
    user_login: "octocat",
    user_avatar_url: "https://avatars.example/1",
  }
  let json = session_to_json(session)
  guard session_from_json(json) is Some(reloaded) else {
    fail("round-trip lost the session")
  }
  assert_true(reloaded.device_token == "odt_secret")
  assert_true(reloaded.server_url == "https://relay.example")
  assert_true(session_from_json(Json::null()) is None)
  assert_true(session_from_json({ "server_url": "x" }) is None)
}

///|
async test "auth.json persists 0600 and deletes cleanly" {
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-auth-"))
  let body = async fn() {
    let session : AuthSession = {
      server_url: "https://relay.example",
      device_token: "odt_secret",
      device_id: "d_abc",
      device_name: "My Mac",
      user_login: "octocat",
      user_avatar_url: "",
    }
    save_session_file(dir, session)
    guard load_session_file(dir) is Some(reloaded) else {
      fail("persisted session did not load")
    }
    assert_true(reloaded.device_id == "d_abc")
    delete_session_file(dir)
    assert_true(load_session_file(dir) is None)
  }
  defer (@fs.rmdir(dir.to_string(), recursive=true) catch { _ => () })
  body()
}

///|
async test "session commit persists before memory and wakes each local transition" {
  let session : AuthSession = {
    server_url: "https://relay.example",
    device_token: "odt_secret",
    device_id: "d_abc",
    device_name: "My Mac",
    user_login: "octocat",
    user_avatar_url: "",
  }
  let store = AuthStore::empty()
  store.commit_session(session)
  assert_true(store.session_server() is Some("https://relay.example"))
  assert_true(store.wakeups().try_get() is Some(_))
  store.connected = true
  store.clear_local_session()
  assert_false(store.connected)
  assert_true(store.session_server() is None)
  assert_true(store.wakeups().try_get() is Some(_))

  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-auth-fail-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let unavailable = root.join("missing")
  let failing = AuthStore::load(runtime_dir=unavailable)
  failing.session = Some({
    server_url: "https://old.example",
    device_token: "old_secret",
    device_id: "d_old",
    device_name: "Old Mac",
    user_login: "octocat",
    user_avatar_url: "",
  })
  failing.connected = true
  try failing.commit_session(session) catch {
    AuthError(_) => ()
    error => raise error
  } noraise {
    _ => fail("commit unexpectedly succeeded without a runtime directory")
  }
  // A failed write exposes neither the new token nor a connector wakeup.
  assert_true(failing.session_server() is Some("https://old.example"))
  assert_true(failing.connected)
  assert_true(failing.wakeups().try_get() is None)
}

///|
test "store transitions dedup their auth.changed edges" {
  let store = AuthStore::empty()
  assert_true(store.desired_connector() is None)
  // Signed-in session drives the connector config.
  store.session = Some({
    server_url: "https://relay.example",
    device_token: "odt_secret",
    device_id: "d_abc",
    device_name: "My Mac",
    user_login: "octocat",
    user_avatar_url: "",
  })
  guard store.desired_connector() is Some(config) else {
    fail("signed-in store offered no connector config")
  }
  assert_true(config.relay_url == "wss://relay.example/v1/tunnel")
  // Registration flips once; a repeat is not a visible change.
  assert_true(store.mark_registered("d_abc"))
  assert_false(store.mark_registered("d_abc"))
  assert_true(store.mark_dropped())
  assert_false(store.mark_dropped())
}

///|
async test "a terminal refusal clears a session but only parks an override" {
  let store = AuthStore::empty()
  store.session = Some({
    server_url: "https://relay.example",
    device_token: "odt_secret",
    device_id: "d_abc",
    device_name: "My Mac",
    user_login: "octocat",
    user_avatar_url: "",
  })
  store.connected = true
  store.handle_refusal()
  assert_true(store.session is None)
  assert_false(store.connected)
  assert_true(store.desired_connector() is None)
  let override_store : AuthStore = {
    runtime_dir: None,
    env_override: Some({
      relay_url: "ws://127.0.0.1:8080/v1/tunnel",
      device_token: "dev",
      device_name: "desktop",
    }),
    app_version: "development",
    wakeups: Queue(kind=DiscardOldest(1)),
    session: None,
    connected: false,
    override_device: None,
    rejected: false,
    sign_in_active: false,
    sign_in_abort: Queue(kind=DiscardOldest(1)),
  }
  assert_true(override_store.desired_connector() is Some(_))
  override_store.handle_refusal()
  assert_true(override_store.desired_connector() is None)
  assert_true(override_store.managed_by_env())
}

///|
test "status shapes" {
  let store = AuthStore::empty(app_version="0.1.16")
  let empty = store.status()
  assert_false(empty.connected)
  assert_eq(empty.server_url, None)
  assert_eq(empty.user, None)
  assert_eq(empty.device, None)
  let configured = store.status(server_url="https://relay.example")
  assert_false(configured.connected)
  assert_eq(configured.server_url, Some("https://relay.example"))
  store.session = Some({
    server_url: "https://relay.example",
    device_token: "odt_secret",
    device_id: "d_abc",
    device_name: "My Mac",
    user_login: "octocat",
    user_avatar_url: "https://avatars.example/1",
  })
  store.connected = true
  let status = store.status()
  assert_true(status.connected)
  assert_eq(status.server_url, Some("https://relay.example"))
  assert_eq(
    status.user,
    Some({ login: "octocat", avatar_url: "https://avatars.example/1", }),
  )
  assert_eq(
    status.device,
    Some({
      id: "d_abc",
      name: "My Mac",
      url: "https://relay.example/console/releases/v0.1.16/index.html?device=d_abc",
    }),
  )
  // The transport encoding must not accidentally disclose the stored token.
  assert_false(status.to_json().stringify().contains("odt_secret"))
}

///|
async test "the loopback listener takes the matching redirect and ignores strays" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let waiter = group.spawn(() => wait_for_code(server, oauth_state="st"))
    // A stray (forged state) answers 404 and keeps the wait alive.
    let (stray, _) = @http.get(
      "http://127.0.0.1:\{port}/cb?code=x&state=forged",
    )
    assert_true(stray.code == 404)
    let browser = group.spawn(() => {
      @http.get("http://127.0.0.1:\{port}/cb?code=one-time&state=st")
    })
    let (code, conn) = waiter.wait()
    defer conn.close()
    assert_true(code == "one-time")
    respond_html(
      conn,
      200,
      "OK",
      sign_in_done_page(
        device_url("https://relay.example", "d_abc", app_version="development"),
      ),
    )
    let (granted, granted_data) = browser.wait()
    assert_true(granted.code == 200)
    let granted_page = granted_data.text()
    // Registration supplies the device id before the browser is released.
    assert_true(
      granted_page.contains("url=https://relay.example/console/?device=d_abc"),
    )
    // The loopback page is self-contained, but its palette stays on the same
    // semantic contract as the app instead of reviving the retired short names.
    assert_true(granted_page.contains("--color-bg-canvas"))
    assert_true(granted_page.contains("--font-family-mono"))
    assert_true(granted_page.contains("--font-family-sans"))
    assert_true(granted_page.contains("font-family: var(--font-family-sans)"))
    assert_false(granted_page.contains("--paper"))
    group.return_immediately(())
  })
}

///|
test "cancel only lands on a live sign-in" {
  let store = AuthStore::empty()
  assert_false(store.cancel_sign_in())
  store.sign_in_active = true
  assert_true(store.cancel_sign_in())
}
