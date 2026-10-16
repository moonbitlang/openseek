// auth.json: the account credential and optional device permission, with
// their issuer and the identity labels the Settings page shows
// without a network round-trip. Lives in the host runtime dir next to
// engine-settings.json, same atomicity and permission rules (0600 temp +
// rename; the file holds a credential).

///|
const AuthFileVersion = 2

///|
const AuthFileName = "auth.json"

///|
fn auth_file(runtime_dir : @pathx.Path) -> @pathx.Path {
  runtime_dir.join(AuthFileName)
}

///|
fn session_to_json(session : AuthSession) -> Json {
  let fields : Map[String, Json] = {
    "version": Json(AuthFileVersion),
    "server_url": Json(session.server_url),
    "account": session.account.to_json(),
  }
  if session.device is Some(device) {
    fields["device"] = {
      "token": device.token,
      "id": device.id,
      "name": device.name,
    }
  }
  Json(fields)
}

///|
/// Version one held a device credential, never an account. Require explicit
/// account sign-in instead of guessing which old Cloud/device identity wins.
fn session_from_json(json : Json) -> AuthSession? {
  guard json
    is {
      "version": 2,
      "server_url": String(server_url),
      "account": account,
      ..
    } &&
    server_url == AccountOrigin else {
    return None
  }
  let account : @protocol.AccountSession = @json.from_json(account) catch {
    _ => return None
  }
  let device = match json {
    {
      "device": {
        "token": String(token),
        "id": String(id),
        "name": String(name),
        ..
      },
      ..
    } => {
      if !token.has_prefix("odt_") || id.is_blank() {
        return None
      }
      Some(DeviceRegistration::{ token, id, name, })
    }
    Object(fields) if fields.contains("device") => return None
    _ => None
  }
  Some({ server_url, account, device, })
}

///|
/// Read the persisted session; absence and corruption both read as signed
/// out.
async fn load_session_file(runtime_dir : @pathx.Path) -> AuthSession? {
  guard (@fsx.try_read_text(auth_file(runtime_dir)) catch { _ => None })
    is Some(text) else {
    return None
  }
  let json = @json.parse(text) catch { _ => return None }
  session_from_json(json)
}

///|
/// Atomic 0600 save, mirroring the engine settings store: temp + rename,
/// with the Windows remove-then-rename fallback.
async fn save_session_file(
  runtime_dir : @pathx.Path,
  session : AuthSession,
) -> Unit {
  let target = auth_file(runtime_dir)
  let temp = runtime_dir.join(AuthFileName + ".tmp")
  let text = session_to_json(session).stringify(indent=2)
  @fs.write_file(
    temp.to_string(),
    text,
    create_mode=CreateOrTruncate,
    permission=0o600,
  ) catch {
    error => raise AuthError("could not write the sign-in file: \{error}")
  }
  @fs.rename(temp.to_string(), target.to_string()) catch {
    _ => {
      @fsx.remove_if_exists(target) catch {
        error => raise AuthError("could not replace the sign-in file: \{error}")
      }
      @fs.rename(temp.to_string(), target.to_string()) catch {
        error => raise AuthError("could not save the sign-in file: \{error}")
      }
    }
  }
}

///|
/// Make sign-out durable before best-effort removal. Truncating the
/// credential to `{}` first means a crash or an unlink failure can leave a
/// file behind, but `load_session_file` will read that marker as signed out
/// instead of restoring the old account credential.
async fn delete_session_file(runtime_dir : @pathx.Path) -> Unit {
  let target = auth_file(runtime_dir)
  @fs.write_file(
    target.to_string(),
    "{}",
    create_mode=CreateOrTruncate,
    permission=0o600,
  ) catch {
    error => raise AuthError("could not clear the sign-in file: \{error}")
  }
  @fsx.remove_if_exists(target) catch {
    error =>
      @xlog.warn(category="auth") <?
        {
          "message": "could not remove the cleared sign-in marker",
          "error": "\{error}",
        }
  }
}
