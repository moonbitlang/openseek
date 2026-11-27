///|
let credential_env_lock : @async.Mutex = Mutex()

///|
fn config(endpoint : String) -> @config.DeviceOAuthConfig {
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
  let identity = @oauth.key("https://example.com/mcp", DeviceCode(c))
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
    assert_false(identity == @oauth.key(resource, DeviceCode(other)))
  }
}

///|
async test "device flow waits persists scoped credentials expires and disconnects" {
  credential_env_lock.acquire()
  defer credential_env_lock.release()
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
    @fs.remove(dir, recursive=true, allow_missing=true)
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
        conn.text.write(json.stringify())
      })
    }
    let c = config("http://127.0.0.1:\{server.local_addr().port}/oauth")
    let resource = "https://example.com/mcp"
    let device = @oauth.device_auth(c)
    assert_eq(device.user_code(), "ABCD")
    assert_eq(device.verification_uri(), "https://example.com/device")
    assert_true(bodies[0].contains("client_id=test%20app%26client"))
    let credential = @oauth.CredentialCommit(DeviceCode(c), resource~)
    let task = group.spawn(() => {
      let token = @oauth.device_access_token(c, device)
      credential.save(token)
    })
    @async.sleep(100)
    assert_eq(bodies.length(), 1)
    task.wait()
    assert_eq(bodies.length(), 3)
    assert_eq(@oauth.token(resource, DeviceCode(c)), Some("test-token"))
    // A completed commit wins over a late cancel; cancel is not disconnect.
    credential.cancel()
    assert_eq(@oauth.token(resource, DeviceCode(c)), Some("test-token"))
    assert_eq(@oauth.token("https://other.com/mcp", DeviceCode(c)), None)
    @async.sleep(1050)
    assert_eq(@oauth.token(resource, DeviceCode(c)), None)
    @oauth.disconnect(resource, DeviceCode(c))
    assert_eq(@oauth.token(resource, DeviceCode(c)), None)
    @oauth.disconnect(resource, DeviceCode(c))
    let expired = @oauth.device_auth(c)
    try @oauth.device_access_token(c, expired) catch {
      error => assert_true("\{error}".contains("expired"))
    } noraise {
      _ => fail("expired authorization was polled")
    }
    assert_eq(bodies.length(), 4)
    let cancelled = @oauth.device_auth(c)
    let credential = @oauth.CredentialCommit(DeviceCode(c), resource~)
    let task = group.spawn(() => {
      let token = @oauth.device_access_token(c, cancelled)
      try credential.save(token) catch {
        error => {
          assert_true("\{error}".contains("cancelled"))
          return
        }
      } noraise {
        _ => fail("cancelled response was accepted")
      }
    })
    requested.get()
    credential.cancel()
    let credential_after_cancel = @oauth.token(resource, DeviceCode(c))
    respond.put(())
    task.wait()
    assert_eq(@oauth.token(resource, DeviceCode(c)), credential_after_cancel)
    assert_eq(credential_after_cancel, None)
    let slow = @oauth.device_auth(c)
    let task = group.spawn(no_wait=true, () => {
      @oauth.device_access_token(c, slow)
    })
    @async.sleep(2100)
    assert_true(task.try_wait() is None)
    assert_eq(bodies.length(), 8)
  }
}

///|
async test "a timed out token request preserves authorization and retries after backoff" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let requests : Array[Int64] = []
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever((_request, conn) => {
        let _ = conn.text.read_all()
        requests.push(@async.now())
        if requests.length() == 2 {
          @async.sleep(60000)
          return
        }
        let reply : Json = if requests.length() == 1 {
          {
            "device_code": "device",
            "user_code": "USER",
            "verification_uri": "https://example.com/device",
            "interval": 1,
            "expires_in": 120,
          }
        } else {
          { "access_token": "recovered", "token_type": "bearer" }
        }
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        conn.text.write(reply.stringify())
      })
    }
    let c = config("http://127.0.0.1:\{server.local_addr().port}/oauth")
    let device = @oauth.device_auth(c)
    let token = @oauth.device_access_token(c, device)
    assert_eq(token.access_token(), "recovered")
    assert_eq(requests.length(), 3)
    assert_true(requests[2] - requests[1] >= 31500)
  }
}
