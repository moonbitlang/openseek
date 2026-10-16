// The pure pieces (PKCE, callback parsing, URLs, the persisted file's
// codec) and the store's transition dedup — everything the live flow in
// signin.mbt is built from.

///|
/// The one signed-in session every codec and store test below uses. The avatar
/// is the only field any of them varies, so it stays an explicit argument.
fn sample_session(avatar~ : String) -> AuthSession {
  {
    server_url: AccountOrigin,
    account: {
      token: "ts_secret",
      user: { user_id: "123", login: "octocat", avatar_url: avatar, },
    },
    device: Some({ token: "odt_secret", id: "d_abc", name: "My Mac", }),
  }
}

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
    ),
    content=(
      #|https://relay.example/v2/auth/account/start?state=st123&code_challenge=ch456&code_challenge_method=S256&port=49152
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
test "auth.json codec round-trips and reads corruption as signed out" {
  let session = sample_session(avatar="https://avatars.example/1")
  let json = session_to_json(session)
  guard session_from_json(json) is Some(reloaded) else {
    fail("round-trip lost the session")
  }
  assert_true(reloaded.account.token == "ts_secret")
  assert_true(reloaded.server_url == AccountOrigin)
  assert_true(session_from_json(Json::null()) is None)
  assert_true(session_from_json({ "server_url": "x" }) is None)
}

///|
async test "auth.json persists 0600 and deletes cleanly" {
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-auth-"))
  let body = () => {
    let session = sample_session(avatar="")
    save_session_file(dir, session)
    if !(@async.platform is Windows) {
      let args = if @async.platform is MacOS {
        ["-f", "%Lp", auth_file(dir).to_string()]
      } else {
        ["-c", "%a", auth_file(dir).to_string()]
      }
      let (code, output, _) = @processx.collect_output_no_stdin("stat", args)
      assert_eq(code, 0)
      assert_eq(output.text().trim().to_owned(), "600")
    }
    let restored = AuthStore::load(runtime_dir=dir)
    assert_true(restored.account() == Some(session.account))
    assert_true(
      restored.desired_connector() is Some({ device_token: "odt_secret", .. }),
    )
    assert_true(AuthStore::load().account() is None)
    guard load_session_file(dir) is Some(reloaded) else {
      fail("persisted session did not load")
    }
    assert_true(reloaded.device is Some({ id: "d_abc", .. }))
    delete_session_file(dir)
    assert_true(load_session_file(dir) is None)
  }
  defer (@fs.rmdir(dir.to_string(), recursive=true) catch { _ => () })
  body()
}

///|
async test "session commit persists before memory and wakes each local transition" {
  let session = sample_session(avatar="")
  let store = AuthStore::empty()
  store.commit_session(session)
  assert_true(store.session_server() == Some(AccountOrigin))
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
    ..sample_session(avatar=""),
    server_url: "https://old.example",
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
  store.session = Some(sample_session(avatar=""))
  guard store.desired_connector() is Some(config) else {
    fail("signed-in store offered no connector config")
  }
  assert_true(config.relay_url == "wss://openseek-api.moonbitlang.cn/v1/tunnel")
  // Registration flips once; a repeat is not a visible change.
  assert_true(store.mark_registered("d_abc"))
  assert_false(store.mark_registered("d_abc"))
  assert_true(store.mark_dropped())
  assert_false(store.mark_dropped())
}

///|
async test "a device refusal preserves the account and parks its connector" {
  let store = AuthStore::empty()
  store.session = Some(sample_session(avatar=""))
  store.connected = true
  store.handle_refusal()
  assert_true(store.account() is Some({ token: "ts_secret", .. }))
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
    persist_mutex: Mutex(),
    remote_generation: 0,
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
  store.session = Some(sample_session(avatar="https://avatars.example/1"))
  store.connected = true
  let status = store.status()
  assert_true(status.connected)
  assert_eq(status.server_url, Some(AccountOrigin))
  assert_eq(
    status.user,
    Some({ login: "octocat", avatar_url: "https://avatars.example/1", }),
  )
  assert_eq(
    status.device,
    Some({
      id: "d_abc",
      name: "My Mac",
      url: "https://openseek-api.moonbitlang.cn/console/releases/v0.1.16/index.html?device=d_abc",
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
    respond_html(conn, 200, "OK", sign_in_done_page())
    let (granted, granted_data) = browser.wait()
    assert_true(granted.code == 200)
    let granted_page = granted_data.text()
    assert_true(granted_page.contains("Return to SeekMoon"))
    assert_false(granted_page.contains("?device="))
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

///|
async test "account login has no device permission and rejects old credentials" {
  let session = { ..sample_session(avatar=""), device: None, }
  let store = AuthStore::empty()
  store.commit_session(session)
  assert_true(store.signed_in())
  assert_true(store.account() is Some({ user: { user_id: "123", .. }, .. }))
  assert_true(store.desired_connector() is None)
  assert_true(store.status().device is None)
  assert_false(store.status().to_json().stringify().contains("ts_secret"))
  assert_true(
    session_from_json({ "version": 1, "device_token": "odt_old" }) is None,
  )
  store.expire_account("ts_stale")
  assert_true(store.signed_in())
}

///|
async test "environment relay survives account login and local sign-out without becoming account authority" {
  let config : ConnectorConfig = {
    relay_url: "ws://127.0.0.1:8080/v1/tunnel",
    device_token: "odt_debug",
    device_name: "Debug",
  }
  let store = AuthStore::load(env_override=config)
  store.mark_registered("debug-device") |> ignore
  store.commit_session({ ..sample_session(avatar=""), device: None, })
  assert_true(store.account() is Some({ token: "ts_secret", .. }))
  assert_true(store.desired_connector() == Some(config))
  assert_true(store.status().connected)
  assert_true(store.wakeups().try_get() is None)
  store.clear_local_session()
  assert_true(store.account() is None)
  assert_true(store.desired_connector() == Some(config))
  assert_true(store.status().connected)
  assert_true(store.wakeups().try_get() is None)
}

///|
async test "account code exchange uses v2 without registering a device" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_true(request.meth is Post)
      assert_eq(request.path, "/v2/auth/account/exchange")
      assert_eq(@json.parse(connection.read_all().text()), {
        "code": "ac_fixture",
        "code_verifier": "verifier",
      })
      connection.send_response(200, "OK")
      connection.write_string(
        "{\"token\":\"ts_fixture\",\"user\":{\"user_id\":\"123\",\"login\":\"octocat\",\"avatar_url\":\"\"}}",
      )
      connection.end_response()
    })
    let session = exchange_code(
      server_url=origin + "/",
      code="ac_fixture",
      verifier="verifier",
    )
    assert_eq(session.server_url, origin)
    assert_eq(session.account.token, "ts_fixture")
    assert_true(session.device is None)
    receiver.wait()
  })
}
