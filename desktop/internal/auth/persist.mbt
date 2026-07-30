// auth.json: the persisted sign-in — which server issued the device token,
// the token itself, and the device/user labels the Settings page shows
// without a network round-trip. Lives in the host runtime dir next to
// engine-settings.json, same atomicity and permission rules (0600 temp +
// rename; the file holds a credential).

///|
const AuthFileVersion = 1

///|
const AuthFileName = "auth.json"

///|
fn auth_file(runtime_dir : @path.Path) -> @path.Path {
  runtime_dir.join(AuthFileName)
}

///|
fn session_to_json(session : AuthSession) -> Json {
  {
    "version": AuthFileVersion.to_json(),
    "server_url": session.server_url.to_json(),
    "device_token": session.device_token.to_json(),
    "device": {
      "id": session.device_id.to_json(),
      "name": session.device_name.to_json(),
    },
    "user": {
      "login": session.user_login.to_json(),
      "avatar_url": session.user_avatar_url.to_json(),
    },
  }
}

///|
/// Tolerant decode: any missing or mistyped field reads as "signed out"
/// rather than wedging startup on a corrupt file.
fn session_from_json(json : Json) -> AuthSession? {
  guard json
    is {
      "server_url": String(server_url),
      "device_token": String(device_token),
      "device": { "id": String(device_id), "name": String(device_name), .. },
      "user": {
        "login": String(user_login),
        "avatar_url": String(user_avatar_url),
        ..
      },
      ..
    } else {
    return None
  }
  Some({
    server_url,
    device_token,
    device_id,
    device_name,
    user_login,
    user_avatar_url,
  })
}

///|
/// Read the persisted session; absence and corruption both read as signed
/// out.
async fn load_session_file(runtime_dir : @path.Path) -> AuthSession? {
  guard (@fsx.try_read_text(auth_file(runtime_dir)) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    })
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
  runtime_dir : @path.Path,
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
    error if @async.is_being_cancelled() => raise error
    error => raise AuthError("could not write the sign-in file: \{error}")
  }
  @fs.rename(temp.to_string(), target.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      @fsx.remove_if_exists(target) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise AuthError("could not replace the sign-in file: \{error}")
      }
      @fs.rename(temp.to_string(), target.to_string()) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise AuthError("could not save the sign-in file: \{error}")
      }
    }
  }
}

///|
/// Make sign-out durable before best-effort removal. Truncating the
/// credential to `{}` first means a crash or an unlink failure can leave a
/// file behind, but `load_session_file` will read that marker as signed out
/// instead of restoring the old device token.
async fn delete_session_file(runtime_dir : @path.Path) -> Unit {
  let target = auth_file(runtime_dir)
  @fs.write_file(
    target.to_string(),
    "{}",
    create_mode=CreateOrTruncate,
    permission=0o600,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise AuthError("could not clear the sign-in file: \{error}")
  }
  @fsx.remove_if_exists(target) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @xlog.warn(category="auth") <?
        {
          "message": "could not remove the cleared sign-in marker",
          "error": "\{error}",
        }
  }
}
