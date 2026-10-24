///|
priv struct AccountPreferences {
  request : Int32
  value : Bool?
  pending : Bool
  error : String?
} derive(Eq)

///|
fn AccountPreferences::empty(request~ : Int32 = 0) -> AccountPreferences {
  { request, value: None, pending: false, error: None, }
}

///|
/// Read only the account setting; never infer consent from a missing field.
fn decode_account_preferences(
  json : Json,
) -> Bool raise @cloud_client.RequestError {
  match json {
    { "allow_content_improvement": True, .. } => true
    { "allow_content_improvement": False, .. } => false
    _ => raise @cloud_client.RequestError(Malformed)
  }
}

///|
fn request_account_preferences(
  dispatch : @cmd.Emit[Msg],
  token : String,
  request : Int32,
  enabled : Bool?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Bool, @cloud_client.Failure] = try {
        let body : Json? = enabled.map(enabled => {
          "allow_content_improvement": enabled,
        })
        Ok(
          decode_account_preferences(
            @cloud_client.request(
              @cloud_client.CloudOrigin,
              "/v1/me/preferences",
              if enabled is Some(_) {
                Patch
              } else {
                Get
              },
              token~,
              body?,
            ),
          ),
        )
      } catch {
        @cloud_client.RequestError(error) => Err(error)
        _ => Err(Unreachable)
      }
      scheduler.add(dispatch(AccountPreferencesLoaded(request, result)))
    })
    |> ignore
  })
}

///|
/// Account changes invalidate every outstanding read/write, including A→B→A.
/// Settings navigation (including browser history) refreshes server-owned state.
fn sync_account_preferences(
  dispatch : @cmd.Emit[Msg],
  previous : Model,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let changed = previous.account_epoch != model.account_epoch ||
    previous.account.map(a => (a.user.user_id, a.token)) !=
    model.account.map(a => (a.user.user_id, a.token))
  let model = if changed {
    {
      ..model,
      account_preferences: AccountPreferences::empty(
        request=model.account_preferences.request + 1,
      ),
    }
  } else {
    model
  }
  let preferences = model.account_preferences
  guard model.screen is Settings &&
    !model.remote_connecting &&
    !model.console.busy &&
    !preferences.pending &&
    (
      changed ||
      previous.screen != Settings ||
      (preferences.value is None && preferences.error is None)
    ) &&
    model.account is Some(account) else {
    return (@cmd.none, model)
  }
  let request = preferences.request + 1
  (
    request_account_preferences(dispatch, account.token, request, None),
    {
      ..model,
      account_preferences: { request, value: None, pending: true, error: None, },
    },
  )
}

///|
fn change_account_preferences(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  enabled : Bool,
) -> (@cmd.Cmd, Model) {
  let preferences = model.account_preferences
  guard model.account is Some(account) &&
    !model.remote_connecting &&
    !model.console.busy &&
    !preferences.pending &&
    preferences.value is Some(current) &&
    current != enabled else {
    return (@cmd.none, model)
  }
  let request = preferences.request + 1
  (
    request_account_preferences(dispatch, account.token, request, Some(enabled)),
    {
      ..model,
      account_preferences: {
        ..preferences,
        request,
        pending: true,
        error: None,
      },
    },
  )
}

///|
fn account_preferences_loaded(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  request : Int32,
  result : Result[Bool, @cloud_client.Failure],
) -> (@cmd.Cmd, Model) {
  let preferences = model.account_preferences
  guard model.account is Some(_) &&
    preferences.pending &&
    preferences.request == request else {
    return (@cmd.none, model)
  }
  if result is Err(Unauthorized as error) {
    let (command, next) = expire_account(dispatch, model)
    return (command, { ..next, remote_error: Some(error.label()), })
  }
  let preferences = match result {
    Ok(value) =>
      { ..preferences, value: Some(value), pending: false, error: None, }
    Err(error) => { ..preferences, pending: false, error: Some(error.label()), }
  }
  (@cmd.none, { ..model, account_preferences: preferences, })
}
