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
      let result : Result[@protocol.AccountSession?, String] = try {
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
            Err(message) => Err(message)
            Ok(Some(account)) => Ok(Some(account))
            Ok(None) if local_console => Ok(None)
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
    console: { ..model.console, busy: false, notice: None, },
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
