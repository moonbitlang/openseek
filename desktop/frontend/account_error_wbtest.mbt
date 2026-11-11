///|
fn account_error_test_account(token : String) -> @protocol.AccountSession {
  { token, user: { user_id: token, login: token, avatar_url: "", }, }
}

///|
/// A relay console page: its sign-in is the Cloud account.
fn relay_console_test_model() -> Model {
  console_test_model()
}

///|
/// A local console page: the host's own sign-in plus an independent Cloud
/// account.
fn local_console_test_model() -> Model {
  { ..console_test_model(), console: empty_console_state(Some("host"), None), }
}

///|
test "a relay account read failure is an account error, not a page-access error" {
  let model = relay_console_test_model()
  let (_, failed) = update(
    test_dispatch(),
    AccountLoaded(
      model.account_epoch,
      Err(Diagnostic("the relay is unreachable")),
    ),
    model,
  )
  assert_eq(failed.account_error, Some(Diagnostic("the relay is unreachable")))
  assert_eq(failed.console.access_error, None)
  assert_true(failed.account_checked)
  assert_true(failed.console.auth is AuthChecking)
}

///|
test "the local console keeps host sign-in failures apart from the Cloud account" {
  let dispatch = test_dispatch()
  let model = local_console_test_model()
  let (_, failed) = update(
    dispatch,
    Console(MeFailed("the sign-in check answered HTTP 500")),
    model,
  )
  assert_eq(
    failed.console.access_error,
    Some("the sign-in check answered HTTP 500"),
  )
  assert_eq(failed.account_error, None)
  // A Cloud account read says nothing about the host's sign-in.
  let (_, loaded) = update(
    dispatch,
    AccountLoaded(failed.account_epoch, Ok(None)),
    failed,
  )
  assert_eq(
    loaded.console.access_error,
    Some("the sign-in check answered HTTP 500"),
  )
  let (_, signed_in) = update(
    dispatch,
    Console(MeLoaded(login="local", avatar="")),
    loaded,
  )
  assert_eq(signed_in.console.access_error, None)
}

///|
test "a failed sign-out lands on the login it was for" {
  let dispatch = test_dispatch()
  let account = account_error_test_account("ts_A")
  let cloud = {
    ..local_console_test_model(),
    account: Some(account),
    console: {
      ..local_console_test_model().console,
      auth: AuthSignedIn(login="local", avatar=""),
      busy: true,
    },
  }
  let (_, failed) = update(
    dispatch,
    Console(SignOutFailed("logout failed", token=Some("ts_A"))),
    cloud,
  )
  assert_eq(failed.account_error, Some(Diagnostic("logout failed")))
  assert_eq(failed.console.access_error, None)
  assert_false(failed.console.busy)
  let host = { ..cloud, account: None, }
  let (_, failed) = update(
    dispatch,
    Console(SignOutFailed("logout failed", token=None)),
    host,
  )
  assert_eq(failed.console.access_error, Some("logout failed"))
  assert_eq(failed.account_error, None)
  assert_false(failed.console.busy)
}

///|
test "starting a sign-out clears both kinds of failure" {
  let model = {
    ..local_console_test_model(),
    account: Some(account_error_test_account("ts_A")),
    account_error: Some(Diagnostic("old account failure")),
    console: {
      ..local_console_test_model().console,
      auth: AuthSignedIn(login="local", avatar=""),
      access_error: Some("old host failure"),
    },
  }
  let (_, signing_out) = update(test_dispatch(), Console(SignOutClicked), model)
  assert_true(signing_out.console.busy)
  assert_eq(signing_out.account_error, None)
  assert_eq(signing_out.console.access_error, None)
}

///|
test "the console retry clears both kinds of failure" {
  let model = {
    ..local_console_test_model(),
    account_error: Some(Diagnostic("account storage is unavailable")),
    console: {
      ..local_console_test_model().console,
      access_error: Some("the relay is unreachable"),
    },
  }
  let (_, retried) = update(test_dispatch(), Console(RefreshClicked), model)
  assert_eq(retried.account_error, None)
  assert_eq(retried.console.access_error, None)
}

///|
test "the account retry rereads the account in every environment" {
  let models = [
    { ..test_model(), is_desktop: true, },
    relay_console_test_model(),
    local_console_test_model(),
  ]
  for model in models {
    let model = {
      ..model,
      account_error: Some(Diagnostic("could not read the account")),
    }
    let (_, retried) = update(test_dispatch(), AccountRetryClicked, model)
    assert_eq(retried.account_error, None)
    assert_eq(retried.account_epoch, model.account_epoch + 1)
    // The retry's own reply settles; the read it replaced cannot.
    let (_, stale) = update(
      test_dispatch(),
      AccountLoaded(model.account_epoch, Err(Diagnostic("stale"))),
      retried,
    )
    assert_eq(stale.account_error, None)
  }
}

///|
test "the account retry waits for a sign-in in flight" {
  let model = {
    ..test_model(),
    is_desktop: true,
    remote_connecting: true,
    account_error: Some(Diagnostic("old failure")),
  }
  let (_, unchanged) = update(test_dispatch(), AccountRetryClicked, model)
  assert_eq(unchanged.account_epoch, model.account_epoch)
  assert_eq(unchanged.account_error, Some(Diagnostic("old failure")))
}

///|
test "the Cloud home learns the account once a read settles" {
  let model = relay_console_test_model()
  assert_false(model.account_checked)
  let (_, signed_out) = update(
    test_dispatch(),
    AccountLoaded(model.account_epoch, Ok(None)),
    model,
  )
  assert_true(signed_out.account_checked)
  assert_eq(signed_out.account_error, None)
}

///|
test "a Remote access failure stays out of the account" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), is_desktop: true, }
  let (_, failed) = update(
    dispatch,
    RemoteAccessSetFailed("bridge down"),
    model,
  )
  assert_eq(failed.remote_access_error, Some("bridge down"))
  assert_eq(failed.account_error, None)
  // An account read leaves the switch's failure in place.
  let (_, loaded) = update(
    dispatch,
    AccountLoaded(failed.account_epoch, Ok(None)),
    failed,
  )
  assert_eq(loaded.remote_access_error, Some("bridge down"))
  let (_, retried) = update(dispatch, RemoteAccessSet(true), loaded)
  assert_eq(retried.remote_access_error, None)
}
