///|
/// The native window reads its account through the bridge. Its authenticated
/// Local Console reads the same live account through the loopback service;
/// relay browsers keep their own account.
fn fetch_account(
  dispatch : @cmd.Emit[Msg],
  desktop : Bool,
  epoch : Int32,
  local_console~ : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.AccountSession?, String] = try {
        if desktop {
          Ok(
            @interop.bridge_request(
              Local,
              @commands.account_session,
              @protocol.NoPayload,
            ).session,
          )
        } else if local_console {
          // This origin inherits Desktop's live account and must never fall
          // back to a credential left by an older browser console.
          @base_browser.local_storage_remove("seekmoon.account.v1") |> ignore
          let url = match resolve_browser_url("/v1/auth/session") {
            Ok((url, _)) => url
            Err(message) => {
              scheduler.add(dispatch(AccountLoaded(epoch, Err(message))))
              return
            }
          }
          let (response, body) = @http.get(url)
          match response.code {
            200 => {
              let reply : @protocol.AccountSessionReply = @json.from_json(
                body.json(),
              )
              Ok(reply.session)
            }
            _ => Err("the Desktop account check answered HTTP \{response.code}")
          }
        } else {
          match load_browser_account() {
            Err(message) => Err(message)
            Ok(Some(account)) => Ok(Some(account))
            Ok(None) => {
              let base = match resolve_browser_url("/v2/auth/me") {
                Ok((url, _)) => url
                Err(message) => {
                  scheduler.add(dispatch(AccountLoaded(epoch, Err(message))))
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
                        dispatch(AccountLoaded(epoch, Err(message))),
                      )
                      return
                    }
                  }
                  let (response, body) = @http.post(url, "")
                  match response.code {
                    200 => Ok(Some(@json.from_json(body.json())))
                    401 => Ok(None)
                    _ => Err("the sign-in check answered HTTP \{response.code}")
                  }
                }
                _ => Err("the sign-in check answered HTTP \{me.code}")
              }
            }
          }
        }
      } catch {
        error =>
          Err(
            if desktop {
              @interop.bridge_error_text(error)
            } else if local_console {
              "the local Console is unreachable: \{@interop.bridge_error_text(error)}"
            } else {
              "the relay is unreachable: \{@interop.bridge_error_text(error)}"
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
  create~ : Bool,
) -> (@cmd.Cmd, Model) {
  guard !model.remote_connecting else { return (@cmd.none, model) }
  let epoch = model.account_epoch + 1
  let command = if model.is_desktop {
    connect_remote(dispatch, epoch)
  } else if model.is_local_console() {
    fetch_account(dispatch, false, epoch, local_console=true)
  } else {
    @cmd.custom_cmd(_ => @dom.window().load_url(model.console.login_url()))
  }
  (
    command,
    {
      ..model,
      account_epoch: epoch,
      account_login_create: if create {
        Some(model.chat_navigation_generation)
      } else {
        None
      },
      remote_connecting: true,
      remote_error: None,
    },
  )
}

///|
fn account_loaded(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  epoch : Int32,
  result : Result[@protocol.AccountSession?, String],
) -> (@cmd.Cmd, Model) {
  guard epoch == model.account_epoch else { return (@cmd.none, model) }
  let account = match result {
    Ok(account) => account
    Err(message) => {
      let (command, export_dialog) = model.export_dialog.account_changed(
        Err(message),
      )
      let (file_command, file_share_dialog) = model.file_share_dialog.account_changed(
        Err(message),
      )
      return (
        @cmd.batch([command, file_command]),
        {
          ..model,
          export_dialog,
          file_share_dialog,
          remote_connecting: false,
          account_login_create: None,
          remote_error: Some(message),
          console: if model.is_desktop || model.is_local_console() {
            model.console
          } else {
            { ..model.console, notice: Some(message), }
          },
        },
      )
    }
  }
  let intent = model.account_login_create
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
    export_dialog,
    file_share_dialog,
    account_login_create: None,
    remote_connecting: false,
    remote_error: None,
  }
  let (retire_command, next) = if changed &&
    !model.is_desktop &&
    !model.is_local_console() {
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
      if account is Some(account) && !model.is_local_console() {
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
  let (console_command, next) = if !model.is_desktop &&
    !model.is_local_console() {
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
  let command = @cmd.batch([
    export_command, file_command, retire_command, command, persistence, console_command,
    remote_status,
  ])
  if account is Some(_) && intent == Some(model.chat_navigation_generation) {
    let (create, next) = update_cloud(dispatch, @cloud.Create, next)
    return (@cmd.batch([command, create]), next)
  }
  (command, next)
}

///|
fn sign_out_account(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  // The inherited account belongs to Desktop. A local browser can reread it,
  // but cannot revoke it through the independent browser logout path.
  if model.is_local_console() {
    return begin_account_login(dispatch, model, create=false)
  }
  if !model.is_desktop {
    guard !model.console.busy else { return (@cmd.none, model) }
    return (
      sign_out(dispatch, token?=model.account.map(account => account.token)),
      {
        ..model,
        console: { ..model.console, busy: true, notice: None, },
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
    { ..next, account_login_create: None, remote_connecting: true, },
  )
}

///|
fn load_browser_account() -> Result[@protocol.AccountSession?, String] {
  match @base_browser.local_storage_get("seekmoon.account.v1") {
    Err(Unavailable) => Err("Account storage is unavailable.")
    Err(AccessFailed(detail)) =>
      Err("Could not read account storage: " + detail)
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
test "Local Console account changes retire Cloud without retiring the launch-authorized host" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("host")
  let base = test_model()
  let console_model = {
    ..base,
    is_desktop: false,
    devices: [{ ..empty_device_state(channel), bridge: Connected, }],
    focused: channel,
    conversations: [{ ..test_conversation(), device: channel, }],
    console: {
      ..base.console,
      page_device: Some("host"),
      auth: AuthSignedIn(login="local", avatar=""),
    },
  }
  let alice : @protocol.AccountSession = {
    token: "ts_alice",
    user: { user_id: "alice", login: "alice", avatar_url: "", },
  }
  let bob : @protocol.AccountSession = {
    token: "ts_bob",
    user: { user_id: "bob", login: "bob", avatar_url: "", },
  }
  let (_, signed_in) = account_loaded(
    dispatch,
    console_model,
    console_model.account_epoch,
    Ok(Some(alice)),
  )
  assert_eq(signed_in.cloud.user_id, Some("alice"))
  let (_, switched) = account_loaded(
    dispatch,
    signed_in,
    signed_in.account_epoch,
    Ok(Some(bob)),
  )
  assert_eq(switched.cloud.user_id, Some("bob"))
  let (_, signed_out) = expire_account(dispatch, switched)
  assert_true(signed_out.account is None)
  assert_true(signed_out.cloud.user_id is None)
  for kept in [signed_in, switched, signed_out] {
    assert_eq(kept.devices.length(), 1)
    assert_true(kept.devices[0].bridge is Connected)
    assert_eq(kept.focused, channel)
    assert_eq(kept.conversations.length(), 1)
    assert_true(kept.console.auth is AuthSignedIn(login="local", ..))
  }
}

///|
test "Local Console account rereads reject older replies and keep host errors independent" {
  let base = test_model()
  let model = {
    ..base,
    is_desktop: false,
    account_epoch: 3,
    console: {
      ..base.console,
      page_device: Some("host"),
      auth: AuthSignedIn(login="local", avatar=""),
    },
  }
  let (_, refreshed) = update_console_msg(
    test_dispatch(),
    RefreshClicked,
    model,
  )
  assert_eq(refreshed.account_epoch, 4)
  let (_, late) = account_loaded(
    test_dispatch(),
    refreshed,
    3,
    Err("old failure"),
  )
  assert_true(late.remote_error is None)
  let (_, failed) = account_loaded(
    test_dispatch(),
    late,
    4,
    Err("account read failed"),
  )
  assert_eq(failed.remote_error, Some("account read failed"))
  assert_true(failed.console.notice is None)
  assert_true(failed.console.auth is AuthSignedIn(..))
}
