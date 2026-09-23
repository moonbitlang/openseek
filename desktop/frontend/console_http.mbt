// The console uses the relay's session-cookie HTTP API. Async's browser
// transport preserves HTTP status codes, including the signed-out 401 signal.

///|
fn console_request(
  path : String,
  method_ : @http.RequestMethod,
  on_done : (Int, String) -> Unit,
  on_fail : (String) -> Unit,
) -> Unit {
  @js.Promise::from_async(() => {
    let url = match resolve_browser_url(path) {
      Ok((url, _)) => url
      Err(message) => {
        on_fail(message)
        return
      }
    }
    let (response, body) = @http.request(url, method_, {}, "") catch {
      error => {
        on_fail(error.to_string())
        return
      }
    }
    // Response.text() uses replacement characters for malformed UTF-8.
    on_done(response.code, @utf8.decode_lossy(body.binary(), ignore_bom=true))
  })
  |> ignore
}

///|
/// GET `/v1/auth/me`: 200 is a session, 401 is signed out, anything else
/// is a page-level failure worth a retry button.
fn fetch_console_me(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    console_request(
      "/v1/auth/me",
      Get,
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 =>
                  match parse_console_me(body) {
                    Some(msg) => msg
                    None =>
                      MeFailed("the sign-in check answered malformed JSON")
                  }
                401 => MeUnauthorized
                _ => MeFailed("the sign-in check answered HTTP \{status}")
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(Console(MeFailed("the relay is unreachable: \{detail}"))),
        )
      },
    )
  })
}

///|
fn parse_console_me(body : String) -> ConsoleMsg? {
  guard (@json.parse(body) catch { _ => return None }) is Object(fields) else {
    return None
  }
  guard @jsonx.json_text(fields, "login") is Some(login) else { return None }
  Some(
    MeLoaded(
      login~,
      avatar=@jsonx.json_text(fields, "avatar_url").unwrap_or(""),
    ),
  )
}

///|
/// GET `/v1/devices`. A 401 here means the session expired between
/// requests — fold it into the signed-out state rather than an error.
fn fetch_console_roster(
  dispatch : @cmd.Emit[Msg],
  generation : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    console_request(
      "/v1/devices",
      Get,
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 =>
                  match parse_console_roster(body) {
                    Some(metas) => RosterLoaded(metas, generation~)
                    None =>
                      RosterFailed(
                        message="the device list answered malformed JSON",
                        generation~,
                      )
                  }
                401 => MeUnauthorized
                _ =>
                  RosterFailed(
                    message="the device list answered HTTP \{status}",
                    generation~,
                  )
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(
            Console(
              RosterFailed(
                message="the relay is unreachable: \{detail}",
                generation~,
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
/// The error line of a failed sign-out: the relay's `{error}` body when it
/// sent one, the HTTP status otherwise.
fn sign_out_error(status : Int, body : String) -> String {
  if (@json.parse(body) catch { _ => Json::null() }) is Object(fields) &&
    @jsonx.json_text(fields, "error") is Some(message) {
    return message
  }
  "the relay answered HTTP \{status}"
}

///|
/// POST `/v1/auth/logout`.
fn sign_out(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    console_request(
      "/v1/auth/logout",
      Post,
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 | 204 => SignOutDone
                401 => MeUnauthorized
                _ => SignOutFailed(sign_out_error(status, body))
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(
            Console(SignOutFailed("the relay is unreachable: \{detail}")),
          ),
        )
      },
    )
  })
}

///|
fn parse_console_roster(body : String) -> Array[DeviceMeta]? {
  guard (@json.parse(body) catch { _ => return None }) is Object(fields) else {
    return None
  }
  guard fields.get("devices") is Some(Array(items)) else { return None }
  let metas : Array[DeviceMeta] = []
  for item in items {
    guard item is Object(device) else { continue }
    guard @jsonx.json_text(device, "id") is Some(id) else { continue }
    metas.push({
      id,
      name: @jsonx.json_text(device, "name").unwrap_or(id),
      hostname: @jsonx.json_text(device, "hostname"),
      online: device.get("online") is Some(True),
    })
  }
  Some(metas)
}
