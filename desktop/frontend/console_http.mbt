// The console's account transport: the relay's session-cookie HTTP API.
// Hand-rolled fetch (rather than rabbita's `@http`) because these flows are
// status-driven — 401 *is* the signed-out signal, and rabbita's package
// treats every completed response as success.

///|
extern "js" fn js_fetch(
  url : String,
  method_ : String,
  has_body : Bool,
  body : String,
  on_done : (Int, String) -> Unit,
  on_fail : (String) -> Unit,
) =
  #| (url, method, hasBody, body, onDone, onFail) => {
  #|   const config = { method };
  #|   if (hasBody) {
  #|     config.headers = { "Content-Type": "application/json" };
  #|     config.body = body;
  #|   }
  #|   fetch(url, config)
  #|     .then((response) => response.text().then((text) => onDone(response.status, text)))
  #|     .catch((error) => onFail(String(error)));
  #| }

///|
/// GET `/v1/auth/me`: 200 is a session, 401 is signed out, anything else
/// is a page-level failure worth a retry button.
fn fetch_console_me(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_fetch(
      "/v1/auth/me",
      "GET",
      false,
      "",
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
    js_fetch(
      "/v1/devices",
      "GET",
      false,
      "",
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
/// The error line of a failed mutation: the relay's `{error}` body when it
/// sent one, the HTTP status otherwise.
fn mutation_error(status : Int, body : String) -> String {
  if (@json.parse(body) catch { _ => Json::null() }) is Object(fields) &&
    @jsonx.json_text(fields, "error") is Some(message) {
    return message
  }
  "the relay answered HTTP \{status}"
}

///|
/// PATCH `/v1/devices/:id` with the new name.
fn rename_device(
  dispatch : @cmd.Emit[Msg],
  device : String,
  name : String,
) -> @cmd.Cmd {
  let body : Json = { "name": name.to_json() }
  @cmd.custom_cmd(scheduler => {
    js_fetch(
      "/v1/devices/\{device}",
      "PATCH",
      true,
      body.stringify(),
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 | 204 => MutationDone
                401 => MeUnauthorized
                _ => MutationFailed(mutation_error(status, body))
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(
            Console(MutationFailed("the relay is unreachable: \{detail}")),
          ),
        )
      },
    )
  })
}

///|
/// DELETE `/v1/devices/:id` — revoke the device's token and drop any live
/// tunnel.
fn delete_device(dispatch : @cmd.Emit[Msg], device : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_fetch(
      "/v1/devices/\{device}",
      "DELETE",
      false,
      "",
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 | 204 => MutationDone
                401 => MeUnauthorized
                _ => MutationFailed(mutation_error(status, body))
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(
            Console(MutationFailed("the relay is unreachable: \{detail}")),
          ),
        )
      },
    )
  })
}

///|
/// POST `/v1/auth/logout`.
fn sign_out(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_fetch(
      "/v1/auth/logout",
      "POST",
      false,
      "",
      (status, body) => {
        scheduler.add(
          dispatch(
            Console(
              match status {
                200 | 204 => SignOutDone
                401 => MeUnauthorized
                _ => MutationFailed(mutation_error(status, body))
              },
            ),
          ),
        )
      },
      detail => {
        scheduler.add(
          dispatch(
            Console(MutationFailed("the relay is unreachable: \{detail}")),
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
