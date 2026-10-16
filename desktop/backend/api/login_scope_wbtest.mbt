///|
async test "a login accepted before disconnect cancels its late returned login id" {
  let cancelled : Array[String] = []
  let scope = ClientLoginScope(id => cancelled.push(id))
  let started : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let admitted = group.spawn(() => {
        try
          scope.invoke("codex.account.login.start", {}, () => {
            started.put(())
            release.get()
            { "loginId": "late", "authUrl": "https://example.test/login" }
          })
        catch {
          @host.HostError(message) => message.contains("closed")
          error => raise error
        } noraise {
          _ => false
        }
      })
      started.get()
      scope.close()
      assert_eq(cancelled, [])
      release.put(())
      assert_true(admitted.wait())
    })
  })
  assert_eq(cancelled, ["late"])
  scope.close()
  assert_eq(cancelled, ["late"])
  let invoked = Ref(false)
  try
    scope.invoke("codex.account.login.start", {}, () => {
      invoked.val = true
      {}
    })
  catch {
    @host.HostError(_) => ()
    error => raise error
  } noraise {
    _ => fail("closed connection cannot start another login")
  }
  assert_false(invoked.val)
  // Durable work accepted by admission must still finish after disconnect.
  assert_eq(
    scope.invoke("agent.start", {}, () => Json("accepted")),
    Json("accepted"),
  )
}

///|
async test "login scope fences other connections and late completion against the current login" {
  let cancelled : Array[String] = []
  let scope = ClientLoginScope(id => cancelled.push(id))
  let other = ClientLoginScope(id => cancelled.push(id))
  ignore(
    scope.invoke("codex.account.login.start", {}, () => { "loginId": "first" }),
  )
  let invoked = Ref(false)
  try
    other.invoke("codex.account.login.cancel", { "loginId": "first" }, () => {
      invoked.val = true
      {}
    })
  catch {
    @host.HostError(_) => ()
    error => raise error
  } noraise {
    _ => fail("another connection must not cancel this login")
  }
  assert_false(invoked.val)
  scope.observe(
    CodexNotification({
      "method": "account/login/completed",
      "params": { "loginId": "first" },
    }),
  )
  ignore(
    scope.invoke("codex.account.login.start", {}, () => {
      // Completion can be delivered before the start response is observed.
      scope.observe(
        CodexNotification({
          "method": "account/login/completed",
          "params": { "loginId": "second" },
        }),
      )
      { "loginId": "second" }
    }),
  )
  ignore(
    scope.invoke("codex.account.login.start", {}, () => { "loginId": "third" }),
  )
  scope.observe(
    CodexNotification({
      "method": "account/login/completed",
      "params": { "loginId": "first" },
    }),
  )
  other.close()
  scope.close()
  assert_eq(cancelled, ["third"])
}

///|
async test "failed login and failed cancellation preserve retry and cleanup semantics" {
  let cancelled : Array[String] = []
  let scope = ClientLoginScope(id => cancelled.push(id))
  try
    scope.invoke("codex.account.login.start", {}, () => {
      raise @host.HostError("invalid login payload")
    })
  catch {
    @host.HostError(_) => ()
    error => raise error
  } noraise {
    _ => fail("invalid payload must fail")
  }
  ignore(
    scope.invoke("codex.account.login.start", {}, () => {
      "error": "unavailable",
    }),
  )
  ignore(
    scope.invoke("codex.account.login.start", {}, () => { "loginId": "retry" }),
  )
  ignore(
    scope.invoke("codex.account.login.cancel", { "loginId": "retry" }, () => {
      "error": "not cancelled",
    }),
  )
  scope.close()
  assert_eq(cancelled, ["retry"])
  let next = ClientLoginScope(id => cancelled.push(id))
  ignore(
    next.invoke("codex.account.login.start", {}, () => {
      "loginId": "cancelled",
    }),
  )
  ignore(
    next.invoke("codex.account.login.cancel", { "loginId": "cancelled" }, () => {}),
  )
  next.close()
  assert_eq(cancelled, ["retry"])
  let attempts : Array[String] = []
  let fail_once = Ref(true)
  let replacement = ClientLoginScope(id => {
    attempts.push(id)
    if fail_once.val {
      fail_once.val = false
      raise @host.HostError("cancellation failed")
    }
  })
  ignore(
    replacement.invoke("codex.account.login.start", {}, () => {
      "loginId": "retain",
    }),
  )
  let started_replacement = Ref(false)
  try
    replacement.invoke("codex.account.login.start", {}, () => {
      started_replacement.val = true
      { "loginId": "not-started" }
    })
  catch {
    @host.HostError(_) => ()
    error => raise error
  } noraise {
    _ => fail("failed cancellation must stop replacement")
  }
  assert_false(started_replacement.val)
  replacement.close()
  assert_eq(attempts, ["retain", "retain"])
}
