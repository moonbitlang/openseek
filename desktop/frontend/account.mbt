///|
/// The native window reads its account through the bridge; browsers own
/// their independent account in this origin's storage.
fn fetch_account(
  dispatch : @cmd.Emit[Msg],
  desktop : Bool,
  epoch : Int32,
  local_console~ : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.AccountSession?, @account_failure.Failure] = try {
        if desktop {
          Ok(
            @interop.bridge_request(
              Local,
              @commands.account_session,
              @protocol.NoPayload,
            ).session,
          )
        } else {
          match load_browser_account() {
            Err(failure) => Err(failure)
            Ok(Some(account)) => Ok(Some(account))
            Ok(None) if local_console => Ok(None)
            Ok(None) => {
              let base = match resolve_browser_url("/v2/auth/me") {
                Ok((url, _)) => url
                Err(message) => {
                  scheduler.add(
                    dispatch(AccountLoaded(epoch, Err(Diagnostic(message)))),
                  )
                  return
                }
              }
              let (me, _) = @http.get(base)
              match me.code {
                401 => Ok(None)
                200 => {
                  let url = match resolve_browser_url("/v2/auth/session") {
                    Ok((url, _)) => url
                    Err(message) => {
                      scheduler.add(
                        dispatch(AccountLoaded(epoch, Err(Diagnostic(message)))),
                      )
                      return
                    }
                  }
                  let (response, body) = @http.post(url, "")
                  match response.code {
                    200 => Ok(Some(@json.from_json(body.json())))
                    401 => Ok(None)
                    _ => Err(SignInCheckHttp(response.code))
                  }
                }
                _ => Err(SignInCheckHttp(me.code))
              }
            }
          }
        }
      } catch {
        error =>
          Err(
            if desktop {
              Bridge(@interop.bridge_problem(error))
            } else {
              RelayUnreachable(@interop.bridge_error_text(error))
            },
          )
      }
      scheduler.add(dispatch(AccountLoaded(epoch, result)))
    })
    |> ignore
  })
}

///|
fn begin_account_login(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard !model.remote_connecting else { return (@cmd.none, model) }
  let epoch = model.account_epoch + 1
  let command = if model.is_desktop {
    connect_remote(dispatch, epoch)
  } else {
    @cmd.custom_cmd(_ => @dom.window().load_url(model.console.login_url()))
  }
  (
    command,
    {
      ..model,
      account_epoch: epoch,
      remote_connecting: true,
      account_login: Some(Waiting),
      account_error: None,
    },
  )
}

///|
test "account sign-in cancellation waits for both replies and ignores stale attempts" {
  for connect_first in [true, false] {
    let initial = { ..test_model(), is_desktop: true, account: None, }
    let (_, pending) = begin_account_login(test_dispatch(), initial)
    let epoch = pending.account_epoch
    let (_, cancelling) = update(test_dispatch(), RemoteCancelClicked, pending)
    let connect_reply = AccountLoginCancelled(epoch)
    let cancel_reply = AccountCancelFinished(epoch)
    let (_, first) = update(
      test_dispatch(),
      if connect_first {
        connect_reply
      } else {
        cancel_reply
      },
      cancelling,
    )
    assert_true(first.remote_connecting)
    assert_true(first.account_login is Some(Cancelling(..)))
    let (_, settled) = update(
      test_dispatch(),
      if connect_first {
        cancel_reply
      } else {
        connect_reply
      },
      first,
    )
    assert_true(settled.remote_connecting)
    assert_true(settled.account_login is None)
    let (_, cancelled) = update(
      test_dispatch(),
      AccountLoaded(epoch, Ok(None)),
      settled,
    )
    assert_false(cancelled.remote_connecting)
    assert_true(cancelled.account_error is None)
    let (_, retried) = begin_account_login(test_dispatch(), cancelled)
    assert_eq(retried.account_epoch, epoch + 1)
    let stale_replies = [
      connect_reply,
      cancel_reply,
      AccountLoginTimedOut(epoch),
      AccountCancelFailed(epoch, Diagnostic("old cancellation failed")),
      AccountLoaded(
        epoch,
        Ok(
          Some({
            token: "old-account-token",
            user: { user_id: "old-user", login: "old-login", avatar_url: "", },
          }),
        ),
      ),
    ]
    for reply in stale_replies {
      let (_, late) = update(test_dispatch(), reply, retried)
      assert_true(late.remote_connecting)
      assert_true(late.account_login is Some(Waiting))
      assert_true(late.account is None)
      assert_true(late.account_error is None)
    }
  }
}

///|
test "account sign-in timeout retains its cause and restores the retry action" {
  let (_, pending) = begin_account_login(test_dispatch(), {
    ..test_model(),
    is_desktop: true,
    account: None,
  })
  let (_, expired) = update(
    test_dispatch(),
    AccountLoginTimedOut(pending.account_epoch),
    pending,
  )
  assert_false(expired.remote_connecting)
  assert_true(expired.account_login is None)
  assert_true(expired.account_error is Some(SignInTimedOut))
  let (_, retried) = begin_account_login(test_dispatch(), expired)
  assert_true(retried.remote_connecting)
  assert_true(retried.account_error is None)
}

///|
test "a failed account cancellation keeps the waiting sign-in cancellable" {
  let (_, pending) = begin_account_login(test_dispatch(), {
    ..test_model(),
    is_desktop: true,
    account: None,
  })
  let (_, cancelling) = update(test_dispatch(), RemoteCancelClicked, pending)
  let (_, failed) = update(
    test_dispatch(),
    AccountCancelFailed(
      pending.account_epoch,
      Diagnostic("bridge disconnected"),
    ),
    cancelling,
  )
  assert_true(failed.remote_connecting)
  assert_true(failed.account_login is Some(Waiting))
  assert_true(failed.account_error is Some(Diagnostic("bridge disconnected")))
  let (_, retried) = update(test_dispatch(), RemoteCancelClicked, failed)
  assert_true(retried.account_login is Some(Cancelling(..)))
  assert_true(retried.account_error is None)
}

///|
fn account_loaded(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  epoch : Int32,
  result : Result[@protocol.AccountSession?, @account_failure.Failure],
) -> (@cmd.Cmd, Model) {
  guard epoch == model.account_epoch else { return (@cmd.none, model) }
  if model.account_login is Some(Cancelling(cancel_pending~, ..)) {
    if cancel_pending {
      return (
        @cmd.none,
        {
          ..model,
          account_login: Some(
            Cancelling(connect_pending=false, cancel_pending=true),
          ),
        },
      )
    }
    // Both operations settled. Read the host's final account in case sign-in
    // committed just before cancellation reached it.
    return (
      fetch_account(dispatch, true, epoch),
      { ..model, account_login: None, },
    )
  }
  let account = match result {
    Ok(account) => account
    Err(failure) => {
      let (command, export_dialog) = model.export_dialog.account_changed(
        Err(failure),
      )
      let (file_command, file_share_dialog) = model.file_share_dialog.account_changed(
        Err(failure),
      )
      return (
        @cmd.batch([command, file_command]),
        {
          ..model,
          export_dialog,
          file_share_dialog,
          remote_connecting: false,
          account_login: None,
          account_checked: true,
          account_error: Some(failure),
        },
      )
    }
  }
  let changed = model.account.map(account => account.token) !=
    account.map(account => account.token)
  let (export_command, export_dialog) = if changed {
    model.export_dialog.account_changed(Ok(()))
  } else {
    (@cmd.none, model.export_dialog)
  }
  let (file_command, file_share_dialog) = if changed {
    model.file_share_dialog.account_changed(Ok(()))
  } else {
    (@cmd.none, model.file_share_dialog)
  }
  let next = {
    ..model,
    account,
    cloud_questions: if changed {
      @user_questions.Model()
    } else {
      model.cloud_questions
    },
    export_dialog,
    file_share_dialog,
    remote_connecting: false,
    account_login: None,
    account_checked: true,
    account_error: None,
    console: { ..model.console, busy: false, },
  }
  let (retire_command, next) = if changed && model.is_relay_console() {
    console_signed_out(dispatch, next)
  } else {
    (@cmd.none, next)
  }
  let (command, next) = if changed {
    update_cloud(
      dispatch,
      @cloud.AccountChanged(account.map(account => account.user.user_id)),
      next,
    )
  } else {
    (@cmd.none, next)
  }
  let persistence = if model.is_desktop {
    @cmd.none
  } else {
    @cmd.custom_cmd(_ => {
      if account is Some(account) {
        @base_browser.local_storage_set(
          "seekmoon.account.v1",
          account.to_json().stringify(),
        )
        |> ignore
      } else {
        @base_browser.local_storage_remove("seekmoon.account.v1") |> ignore
      }
    })
  }
  let (console_command, next) = if model.is_relay_console() {
    match account {
      Some(account) =>
        update_console_msg(
          dispatch,
          MeLoaded(login=account.user.login, avatar=account.user.avatar_url),
          next,
        )
      None if !changed => console_signed_out(dispatch, next)
      None => (@cmd.none, next)
    }
  } else {
    (@cmd.none, next)
  }
  let remote_status = if changed && model.is_desktop && account is Some(_) {
    fetch_remote_status(dispatch)
  } else {
    @cmd.none
  }
  // The Cloud skills mirror belongs to one account: drop the old one and read
  // the new one, which the Cloud composer's `$` completion lists.
  let (skills_command, next) = if changed {
    let next = { ..next, cloud_skills: [], }
    (
      next
      .cloud_skills_access()
      .map_or(@cmd.none, access => {
        fetch_cloud_skills(dispatch, access, next.locale)
      }),
      next,
    )
  } else {
    (@cmd.none, next)
  }
  // A browser's push state belongs to the account it registers with; a new
  // sign-in probes again, and the probe re-registers an existing
  // subscription for it.
  let push_changed = changed && !model.is_desktop
  let push_command = if push_changed && account is Some(_) {
    @web_push.probe(dispatch.map(msg => WebPush(msg)))
  } else {
    @cmd.none
  }
  let next = if push_changed {
    { ..next, web_push: @web_push.State(), }
  } else {
    next
  }
  let command = @cmd.batch([
    export_command, file_command, retire_command, command, persistence, console_command,
    remote_status, skills_command, push_command,
  ])
  (command, next)
}

///|
fn sign_out_account(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  if !model.is_desktop {
    guard !model.console.busy else { return (@cmd.none, model) }
    return (
      sign_out(dispatch, token?=model.account.map(account => account.token)),
      {
        ..model,
        account_error: None,
        console: { ..model.console, busy: true, access_error: None, },
        account_preferences: AccountPreferences::empty(
          request=model.account_preferences.request + 1,
        ),
      },
    )
  }
  let epoch = model.account_epoch + 1
  let (reset, next) = account_loaded(
    dispatch,
    { ..model, account_epoch: epoch, },
    epoch,
    Ok(None),
  )
  (
    @cmd.batch([reset, disconnect_remote(dispatch, epoch)]),
    { ..next, remote_connecting: true, },
  )
}

///|
fn load_browser_account() -> Result[
  @protocol.AccountSession?,
  @account_failure.Failure,
] {
  match @base_browser.local_storage_get("seekmoon.account.v1") {
    Err(Unavailable) => Err(StorageUnavailable)
    Err(AccessFailed(detail)) => Err(StorageReadFailed(detail))
    Ok(None) => Ok(None)
    Ok(Some(text)) =>
      Ok(
        Some((@json.from_json(@json.parse(text)) : @protocol.AccountSession)) catch {
          _ => None
        },
      )
  }
}

///|
/// A rejected credential is retired without signing out an unrelated browser
/// cookie. Explicit browser logout clears state only after its HTTP succeeds.
fn expire_account(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  if model.is_desktop {
    sign_out_account(dispatch, model)
  } else {
    let epoch = model.account_epoch + 1
    account_loaded(
      dispatch,
      { ..model, account_epoch: epoch, },
      epoch,
      Ok(None),
    )
  }
}

///|
test "a local browser account reset preserves the host and rejects stale results" {
  let base = test_model()
  let channel : @interop.ChannelId = Remote("host")
  let account : @protocol.AccountSession = {
    token: "ts_browser-token",
    user: { user_id: "browser", login: "browser", avatar_url: "", },
  }
  let model = {
    ..base,
    is_desktop: false,
    account: Some(account),
    account_epoch: 2,
    devices: [{ ..empty_device_state(channel), bridge: Connected, }],
    focused: channel,
    conversations: [{ ..test_conversation(), device: channel, }],
    console: {
      ..base.console,
      page_device: Some("host"),
      auth: AuthSignedIn(login="local", avatar=""),
      busy: true,
    },
  }
  let (_, stale) = account_loaded(test_dispatch(), model, 1, Ok(None))
  assert_true(stale == model)
  let (_, signed_out) = account_loaded(test_dispatch(), model, 2, Ok(None))
  let (_, repeated) = account_loaded(test_dispatch(), model, 2, Ok(None))
  assert_true(signed_out == repeated)
  assert_true(signed_out.account is None)
  assert_false(signed_out.console.busy)
  assert_true(signed_out.devices == model.devices)
  assert_true(signed_out.conversations == model.conversations)
  assert_true(signed_out.console.auth == model.console.auth)
}
