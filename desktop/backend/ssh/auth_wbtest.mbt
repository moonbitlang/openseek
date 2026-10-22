///|
async test "SSH unavailable helper reports its actionable cause and retires the connection" {
  let connection = Connection(
    { id: "one", command: "ssh host", display_name: None, projects: None, },
    1,
  )
  let events : Array[Json] = []
  connection.run(event => events.push(event))
  assert_true(
    events ==
    [
      {
        "disconnected": "SSH connection failed: SSH authentication helper is unavailable in this host",
      },
    ],
  )
  assert_false(connection.active())
  assert_true(connection.waiter is None)
}

///|
test "SSH prompts preserve actual targets and only explicit password rejection is a retry" {
  let password = auth_request("alice@jump's password: ", "", 1, false)
  assert_eq(password.target, Some("alice@jump"))
  assert_true(password.kind is Password)
  assert_false(password.retry)
  assert_true(auth_request(password.prompt, "", 2, true).retry)
  let passphrase = auth_request(
    "Enter passphrase for key '/tmp/private key': ", "", 3, true,
  )
  assert_true(passphrase.kind is Passphrase)
  assert_eq(passphrase.target, Some("/tmp/private key"))
  assert_false(passphrase.retry)
  let otp = auth_request("Verification code: ", "", 4, true)
  assert_true(otp.kind is Challenge)
  assert_eq(otp.target, None)
  assert_false(otp.retry)
  for
    prompt in [
      "Are you sure you want to continue connecting (yes/no/[fingerprint])? ", "Trust this key?",
    ] {
    let request = auth_request(prompt, "confirm", 5, true)
    assert_true(request.kind is Confirm)
    assert_eq(request.prompt, prompt)
    assert_false(request.retry)
  }
}

///|
async test "SSH waiter rejects cross host stale and duplicate answers and cancellation retires it" {
  let connection = Connection(
    { id: "one", command: "ssh host", display_name: None, projects: None, },
    9,
    attempt=2,
  )
  let queue : @async.Queue[@protocol.SshAuthAnswer] = Queue(kind=Blocking(1))
  connection.waiter = Some({
    request: auth_request("Password:", "", 3, false),
    answer: queue,
  })
  let response : @protocol.SshAuthResponse = {
    host_id: "one",
    attempt: 2,
    epoch: 9,
    request_id: 3,
    answer: Value(""),
  }
  for
    stale in [
      { ..response, host_id: "two", },
      { ..response, attempt: 1, },
      { ..response, epoch: 8, },
      { ..response, request_id: 2, },
    ] {
    assert_true(connection.respond(stale) is SshUnsent(_))
    assert_true(connection.waiter is Some(_))
  }
  assert_true(
    connection.respond({ ..response, answer: Accept, }) is SshRefused(_),
  )
  assert_true(connection.respond(response) is SshSuccess(_))
  assert_true(connection.respond(response) is SshUnsent(_))
  assert_true(queue.get() is Value(""))
  let confirm : AuthWaiter = {
    request: auth_request("Trust host?", "confirm", 4, false),
    answer: Queue(kind=Blocking(1)),
  }
  connection.waiter = Some(confirm)
  assert_true(
    connection.respond({ ..response, request_id: 4, }) is SshRefused(_),
  )
  assert_true(
    connection.respond({ ..response, request_id: 4, answer: Cancel, })
    is SshSuccess(_),
  )
  assert_true(confirm.answer.get() is Cancel)
  assert_false(connection.active())
  assert_true(connection.waiter is None)
  assert_true(
    connection.respond({ ..response, request_id: 4, answer: Accept, })
    is SshUnsent(_),
  )
}

///|
async test "SSH IPC rejects unrelated peers and serializes challenge delivery through cancellation" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let connection = Connection(
        { id: "ipc", command: "ssh demo", display_name: None, projects: None, },
        1,
        attempt=1,
      )
      defer connection.close()
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let events : @async.Queue[Json] = Queue(kind=Blocking(8))
      group.spawn_bg(() => {
        connection.serve_auth(server, "private-token", value => {
          ignore(events.try_put(value) catch { _ => false })
        })
      })
      let unrelated = @socket.Tcp::connect(server.addr)
      defer unrelated.close()
      unrelated.write("{\"token\":\"wrong\",\"prompt\":\"p\",\"hint\":\"\"}\n")
      assert_eq(unrelated.read_some(), None)
      assert_true(connection.waiter is None)
      let helper = @socket.Tcp::connect(server.addr)
      defer helper.close()
      helper.write(
        "{\"token\":\"private-token\",\"prompt\":\"demo's password: \",\"hint\":\"\"}\n",
      )
      assert_true(
        events.get()
        is { "authentication": { "request_id": 1, "kind": "password", .. }, .. },
      )
      assert_true(
        connection.respond({
          host_id: "ipc",
          attempt: 1,
          epoch: 1,
          request_id: 1,
          answer: Value("temporary-test-value"),
        })
        is SshSuccess(_),
      )
      assert_true(
        auth_frame(helper) ==
        { "action": "value", "value": "temporary-test-value" },
      )
      assert_true(events.get() == { "authentication_submitted": 1 })
      assert_true(connection.waiter is None)
      let next = @socket.Tcp::connect(server.addr)
      defer next.close()
      next.write(
        "{\"token\":\"private-token\",\"prompt\":\"Code:\",\"hint\":\"\"}\n",
      )
      assert_true(
        events.get()
        is {
          "authentication": { "request_id": 2, "kind": "challenge", .. },
          ..
        },
      )
      connection.close()
      assert_true(auth_frame(next) == { "action": "cancel" })
      assert_true(connection.waiter is None)
      group.return_immediately(())
    })
  })
}
