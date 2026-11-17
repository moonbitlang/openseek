///|
fn config(endpoint : String) -> @config.OAuthConfig {
  {
    client_id: "test app&client",
    device_authorization_endpoint: endpoint,
    token_endpoint: endpoint,
    scopes: "repo read:org",
  }
}

///|
test "credential identities separate resources clients endpoints and scopes" {
  let c = config("https://example.com/token")
  let identity = @oauth.key("https://example.com/mcp", c)
  for
    (resource, other) in [
      ("https://other.com/mcp", c),
      ("https://example.com/mcp", { ..c, client_id: "other", }),
      (
        "https://example.com/mcp",
        { ..c, token_endpoint: "https://other.com/token", },
      ),
      ("https://example.com/mcp", { ..c, scopes: "admin", }),
    ] {
    assert_false(identity == @oauth.key(resource, other))
  }
}

///|
async test "device flow waits persists scoped credentials expires and disconnects" {
  let original = @env.get_env_var("OPENSEEK_OAUTH_DIR")
  guard @env.rand(16) is Some(random) else { fail("randomness unavailable") }
  let dir = "/tmp/openseek-oauth-test-" + @crypto.bytes_to_hex_string(random)
  @env.set_env_var("OPENSEEK_OAUTH_DIR", dir)
  defer {
    if original is Some(value) {
      @env.set_env_var("OPENSEEK_OAUTH_DIR", value)
    } else {
      @env.unset_env_var("OPENSEEK_OAUTH_DIR")
    }
    @fs.rmdir(dir, recursive=true, allow_missing=true)
  }
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let bodies : Array[String] = []
    let requested : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let respond : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let responses : Array[Json] = [
      {
        "device_code": "secret-device",
        "user_code": "ABCD",
        "verification_uri": "https://example.com/device",
        "expires_in": 60,
        "interval": 1,
      },
      { "error": "authorization_pending" },
      { "access_token": "test-token", "token_type": "bearer", "expires_in": 1 },
      {
        "device_code": "expiring",
        "user_code": "EFGH",
        "verification_uri": "https://example.com/device",
        "expires_in": 1,
        "interval": 1,
      },
      {
        "device_code": "cancel-me",
        "user_code": "IJKL",
        "verification_uri": "https://example.com/device",
        "expires_in": 60,
        "interval": 1,
      },
      { "access_token": "must-not-save", "token_type": "bearer" },
      {
        "device_code": "slow",
        "user_code": "MNOP",
        "verification_uri": "https://example.com/device",
        "expires_in": 60,
        "interval": 1,
      },
      { "error": "slow_down" },
    ]
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, conn) => {
        bodies.push(conn.text.read_all())
        if bodies.length() == 6 {
          requested.put(())
          respond.get()
        }
        let json = responses[bodies.length() - 1]
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        conn.write_string(json.stringify())
      })
    }
    let c = config("http://127.0.0.1:\{server.addr.port()}/oauth")
    let resource = "https://example.com/mcp"
    let pending = @oauth.begin(c)
    assert_eq(pending.user_code(), "ABCD")
    assert_true(bodies[0].contains("client_id=test%20app%26client"))
    assert_true(@oauth.poll(pending, resource, c) is Waiting)
    assert_eq(bodies.length(), 1)
    @async.sleep(1050)
    assert_true(@oauth.poll(pending, resource, c) is Waiting)
    @async.sleep(1050)
    assert_true(@oauth.poll(pending, resource, c) is Authorized)
    assert_eq(@oauth.token(resource, c), Some("test-token"))
    assert_eq(@oauth.token("https://other.com/mcp", c), None)
    @async.sleep(1050)
    assert_eq(@oauth.token(resource, c), None)
    @oauth.disconnect(resource, c)
    assert_eq(@oauth.token(resource, c), None)
    @oauth.disconnect(resource, c)
    let expired = @oauth.begin(c)
    @async.sleep(1050)
    try @oauth.poll(expired, resource, c) catch {
      error => assert_true("\{error}".contains("expired"))
    } noraise {
      _ => fail("expired authorization was polled")
    }
    assert_eq(bodies.length(), 4)
    let cancelled = @oauth.begin(c)
    @async.sleep(1050)
    let task = group.spawn(() => {
      try @oauth.poll(cancelled, resource, c) catch {
        error => {
          assert_true("\{error}".contains("cancelled"))
          return
        }
      } noraise {
        _ => fail("cancelled response was accepted")
      }
    })
    requested.get()
    cancelled.cancel()
    respond.put(())
    task.wait()
    assert_eq(@oauth.token(resource, c), None)
    let slow = @oauth.begin(c)
    @async.sleep(1050)
    assert_true(@oauth.poll(slow, resource, c) is Waiting)
    @async.sleep(1050)
    assert_true(@oauth.poll(slow, resource, c) is Waiting)
    assert_eq(bodies.length(), 8)
  }
}
