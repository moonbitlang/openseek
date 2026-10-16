///|
priv suberror ExportError {
  ExportError(String)
  AccountUnauthorized
}

///|
impl Show for ExportError with fn output(self, logger) {
  match self {
    ExportError(message) => logger.write_string(message)
    AccountUnauthorized => logger.write_string("Your account sign-in expired.")
  }
}

///|
/// Capture the client account and source once. The owning host captures and
/// publishes the snapshot; the client sends account or upload-grant authority.
fn Model::share(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : Source,
  account : @protocol.AccountSession,
  desktop~ : Bool,
) -> @cmd.Cmd {
  let generation = self.generation
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = try {
        let crypto : @js.Value = @js.globalThis.get_with_string("crypto")
        let first : String = crypto.apply_with_string(
          "randomUUID",
          ([] : FixedArray[@js.Value]),
        )
        let second : String = crypto.apply_with_string(
          "randomUUID",
          ([] : FixedArray[@js.Value]),
        )
        let idempotency_key = (first + second).replace_all(old="-", new="")
        match source {
          Host(channel, payload) => {
            let authorization : @protocol.ShareAuthorization = match channel {
              Local => LocalAccount(user_id=account.user.user_id)
              Remote(device) =>
                upload_grant(device, idempotency_key, account.token, desktop~)
            }
            @interop.bridge_request(channel, @commands.session_share, {
              generation,
              source: payload,
              idempotency_key,
              authorization,
            })
          }
        }
      } catch {
        AccountUnauthorized => @protocol.SignInRequired
        error => @protocol.Failed(message=@interop.bridge_error_text(error))
      }
      scheduler.add(emit(Published(generation~, reply)))
    })
    |> ignore
  })
}

///|
/// Browsers use their own API origin; Proton uses the fixed account issuer.
async fn upload_grant(
  device : String,
  idempotency_key : String,
  token : String,
  desktop~ : Bool,
) -> @protocol.ShareAuthorization {
  let base : String = if desktop {
    "https://openseek-api.moonbitlang.cn/"
  } else {
    @js.Value::cast_from(@dom.document()).get_with_string("baseURI")
  }
  let url = match @base_browser.resolve_url("/v2/shares/upload-grants", base~) {
    Ok((url, _)) => url
    Err(message) => raise ExportError(message)
  }
  let body : Json = { "device_id": device, "idempotency_key": idempotency_key }
  let (response, result) = @http.post(url, body.stringify(), headers={
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json",
  })
  if response.code == 401 {
    raise AccountUnauthorized
  }
  guard response.code == 201 else {
    raise ExportError(
      "Could not prepare sharing (HTTP \{response.code}). Try sharing again.",
    )
  }
  let json = result.json() catch {
    _ => raise ExportError("Invalid share upload permission.")
  }
  guard json
    is {
      "upload_token": String(upload_token),
      "expires_in": Number(expires_in, ..),
      ..
    } &&
    upload_token.has_prefix("sug_") &&
    expires_in > 0 &&
    expires_in == expires_in.to_int().to_double() else {
    raise ExportError("Invalid share upload permission.")
  }
  @protocol.UploadGrant(upload_token~)
}

///|
async fn capture(source : Source) -> @protocol.SessionSnapshot {
  match source {
    Host(channel, payload) =>
      @interop.bridge_request(channel, @commands.session_snapshot, payload)
  }
}

///|
fn Model::download(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : Source,
  desktop~ : Bool,
) -> @cmd.Cmd {
  let generation = self.generation
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionExportReply, String] = try {
        let reply = if desktop && source is Host(Local, payload) {
          @interop.bridge_request(Local, @commands.session_export, payload)
        } else {
          let files = capture(source)
          if desktop {
            @interop.bridge_request(Local, @commands.session_snapshot_save, {
              session: match source {
                Host(_, payload) => payload.session
              },
              html: files.html,
            })
          } else {
            let blob = @dom.Blob::from_bytes(
              @utf8.encode(files.html),
              "text/html;charset=utf-8",
            )
            let urls : @js.Value = @js.globalThis.get_with_string("URL")
            let url : String = urls.apply_with_string("createObjectURL", [
              @js.Value::cast_from(blob),
            ])
            let anchor = @dom.document().create_element("a")
            anchor.set_attribute("href", url)
            anchor.set_attribute("download", "conversation.html")
            if anchor.to_html_element() is Some(element) {
              element.click()
            }
            @base_browser.schedule_timeout(
              () => {
                let _ : Unit = urls.apply_with_string("revokeObjectURL", [
                  @js.Value::cast_from(url),
                ])
              },
              1000,
            )
            |> ignore
            @protocol.SessionExportReply::{
              path: Some("conversation.html"),
              opened: false,
            }
          }
        }
        Ok(reply)
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(Downloaded(generation~, result)))
    })
    |> ignore
  })
}

///|
/// Only native sign-in can be cancelled through this window's bridge.
fn cancel_sign_in() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request(
        Local,
        @commands.auth_cancel,
        @protocol.NoPayload,
      ) catch {
        _ => return
      }
    })
    |> ignore
  })
}
