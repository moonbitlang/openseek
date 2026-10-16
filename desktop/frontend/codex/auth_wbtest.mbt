///|
test "Codex authentication replies cannot escape their connection and login generation" {
  let initial = { ..State(), loading: false, connection: CodexReady, }
  let current = initial.begin_auth()
  let current = current.begin_foreground(
    CodexLoginReply(current.auth_context()),
  )
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let opened : Array[String] = []
  for
    context in [
      initial.auth_context(),
      {
        ..current.auth_context(),
        connection_epoch: current.activity.connection_epoch + 1,
      },
    ] {
    for
      message in [
        Reply(kind=CodexAccountReply(context), value={
          "account": Json::null(),
          "requiresOpenaiAuth": true,
        }),
        Reply(kind=CodexLoginReply(context), value={
          "loginId": "old",
          "authUrl": "https://example.test/old",
        }),
        Failed(kind=CodexLoginReply(context), message="late error"),
      ] {
      let (_, next) = update(dispatch, message, current, @interop.Local, url => {
        opened.push(url)
        @cmd.none
      })
      assert_true(next == current)
    }
  }
  assert_eq(opened, [])
  let (_, ready) = update(
    dispatch,
    Reply(kind=CodexLoginReply(current.auth_context()), value={
      "loginId": "current",
      "authUrl": "https://example.test/current",
    }),
    current,
    @interop.Local,
    url => {
      opened.push(url)
      @cmd.none
    },
  )
  assert_eq(opened, ["https://example.test/current"])
  assert_eq(ready.login_id, Some("current"))
  assert_false(ready.loading)
}

///|
test "only the current login completion settles the URL and native failure survives account refresh" {
  let initial = {
    ..State(),
    loading: false,
    connection: CodexReady,
    login_id: Some("current"),
    auth_url: Some("https://example.test/current"),
  }
  let pending = initial.begin_foreground(
    CodexCancelLoginReply("current", initial.auth_context()),
  )
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let no_open = _ => @cmd.none
  let (_, stale) = update(
    dispatch,
    Notification(
      method_="account/login/completed",
      params={ "loginId": "old", "success": true },
      generation=1,
    ),
    pending,
    @interop.Local,
    no_open,
  )
  assert_eq(stale.login_id, Some("current"))
  assert_eq(stale.auth_url, pending.auth_url)
  assert_true(stale.loading)
  let (_, finished) = update(
    dispatch,
    Notification(
      method_="account/login/completed",
      params={ "loginId": "current", "success": false, "error": "cancelled" },
      generation=1,
    ),
    stale,
    @interop.Local,
    no_open,
  )
  assert_eq(finished.login_id, None)
  assert_eq(finished.auth_url, None)
  assert_false(finished.loading)
  let (_, failed) = update(
    dispatch,
    Notification(
      method_="seekmoon/login_failed",
      params={ "loginId": "current", "message": "callback tunnel expired" },
      generation=1,
    ),
    finished,
    @interop.Local,
    no_open,
  )
  let (_, refreshed) = update(
    dispatch,
    Reply(kind=CodexAccountReply(failed.auth_context()), value={
      "account": Json::null(),
      "requiresOpenaiAuth": true,
    }),
    failed,
    @interop.Local,
    no_open,
  )
  assert_eq(refreshed.notice, "callback tunnel expired")
  let catalog = refreshed.with_threads(
    { "data": [], "nextCursor": Json::null() },
    false,
    refreshed.activity.frontier(),
  )
  assert_eq(catalog.authentication_error(), Some("callback tunnel expired"))
  assert_true(refreshed.account is CodexSignedOut(true))
  let (_, starting) = update(
    dispatch,
    Login,
    refreshed,
    @interop.Local,
    no_open,
  )
  let (_, late) = update(
    dispatch,
    Notification(
      method_="seekmoon/login_failed",
      params={ "loginId": "current", "message": "old failure" },
      generation=1,
    ),
    starting,
    @interop.Local,
    no_open,
  )
  assert_true(late == starting)
  assert_eq(late.notice, "")
  assert_eq(late.authentication_error(), None)
}

///|
test "Codex reconnect clears retired login state and only its own foreground lock" {
  let initial = { ..State(), loading: false, connection: CodexReady, }
  let logging_in = initial.begin_foreground(
    CodexLoginReply(initial.auth_context()),
  )
  let reconnected = logging_in.bridge_reconnected()
  assert_false(reconnected.loading)
  assert_true(reconnected.foreground is None)
  assert_false(
    reconnected.accepts_reply(CodexLoginReply(initial.auth_context())),
  )
  let working = {
    ..initial.begin_foreground(CodexTurnStartReply("thread")),
    notice: "unrelated turn error",
    login_id: Some("pending"),
    auth_url: Some("https://example.test/login"),
  }
  let retained = working.bridge_reconnected()
  assert_eq(retained.authentication_error(), None)
  assert_eq(retained.notice, "unrelated turn error")
  assert_eq(retained.login_id, None)
  assert_eq(retained.auth_url, None)
  assert_true(retained.loading)
  assert_true(retained.foreground is Some(CodexTurnForeground("thread")))
}

///|
test "remote configuration replies are scoped to the working host connection" {
  let initial = State()
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let no_open = _ => @cmd.none
  let (_, loading) = update(
    dispatch,
    PrepareConfig,
    initial,
    @interop.Local,
    no_open,
  )
  assert_true(loading.config_view() is ConfigLoading)
  let (_, duplicate) = update(
    dispatch,
    PrepareConfig,
    loading,
    @interop.Local,
    no_open,
  )
  assert_true(duplicate == loading)
  let reply = Reply(kind=CodexConfigReply(initial.activity.connection_epoch), value={
    "path": "/remote/codex/config.toml",
    "terminal_login": {
      "kind": "ready",
      "command": "remote-login-command",
      "device_auth": true,
    },
  })
  let (_, ready) = update(dispatch, reply, loading, @interop.Local, no_open)
  assert_true(
    ready.config_view()
    is ConfigReady(
      {
        path: "/remote/codex/config.toml",
        terminal_login: Ok(("remote-login-command", true)),
      }
    ),
  )
  let (_, unavailable) = update(
    dispatch,
    Reply(kind=CodexConfigReply(initial.activity.connection_epoch), value={
      "path": "/remote/codex/config.toml",
      "terminal_login": { "kind": "unavailable", "message": "CLI missing" },
    }),
    loading,
    @interop.Local,
    no_open,
  )
  assert_true(
    unavailable.config_view()
    is ConfigReady(
      { path: "/remote/codex/config.toml", terminal_login: Err("CLI missing"), }
    ),
  )
  let retired = loading.bridge_reconnected()
  let (_, stale) = update(dispatch, reply, retired, @interop.Local, no_open)
  assert_true(stale == retired)
  let (_, stale_error) = update(
    dispatch,
    Failed(
      kind=CodexConfigReply(initial.activity.connection_epoch),
      message="old error",
    ),
    retired,
    @interop.Local,
    no_open,
  )
  assert_true(stale_error == retired)
}

///|
test "manual account refresh fences prior status and preserves an active browser login" {
  let initial = { ..State(), loading: false, connection: CodexReady, }
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let no_open = _ => @cmd.none
  let (_, refreshing) = update(
    dispatch,
    RefreshAccount,
    initial,
    @interop.Local,
    no_open,
  )
  let (_, stale) = update(
    dispatch,
    Reply(kind=CodexAccountReply(initial.auth_context()), value={
      "account": Json::null(),
      "requiresOpenaiAuth": true,
    }),
    refreshing,
    @interop.Local,
    no_open,
  )
  assert_true(stale == refreshing)
  let (_, current) = update(
    dispatch,
    Reply(kind=CodexAccountReply(refreshing.auth_context()), value={
      "account": {
        "type": "chatgpt",
        "email": "qa@example.test",
        "planType": "plus",
      },
      "requiresOpenaiAuth": false,
    }),
    refreshing,
    @interop.Local,
    no_open,
  )
  assert_true(current.signed_in())
  let pending = {
    ..initial,
    login_id: Some("current-login"),
    auth_url: Some("https://example.test/login"),
  }
  let (_, unchanged) = update(
    dispatch,
    RefreshAccount,
    pending,
    @interop.Local,
    no_open,
  )
  assert_true(unchanged == pending)
}
