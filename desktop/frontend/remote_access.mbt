// The host's relay sign-in, over the wire: `auth.status` seeds the mirror
// at bridge time, `auth.connect`/`auth.disconnect` drive it from the
// Settings page, and the `auth.changed` broadcast keeps it fresh (decoded
// in bridge.mbt through the same `decode_remote_access`). Desktop-window
// ops by convention — a browser signs in with the relay directly — so every
// call here is pinned to the `Local` channel: the section describes this
// host's own relay registration, never a focused remote device's.

///|
/// Decode one status payload (a reply's JSON or a broadcast's params).
/// `connected` is the shape's one required field.
fn decode_remote_access(payload : Map[String, Json]) -> RemoteAccess? {
  guard payload.get("connected") is Some(connected) &&
    connected is (True | False) else {
    return None
  }
  let (user_login, device_name, device_url) = {
    let login = match payload.get("user") {
      Some(Object(user)) => @jsonx.json_text(user, "login")
      _ => None
    }
    match payload.get("device") {
      Some(Object(device)) =>
        (
          login,
          @jsonx.json_text(device, "name"),
          @jsonx.json_text(device, "url"),
        )
      _ => (login, None, None)
    }
  }
  Some({
    server_url: @jsonx.json_text(payload, "server_url"),
    connected: connected is True,
    managed_by_env: payload.get("managed_by_env") is Some(True),
    user_login,
    device_name,
    device_url,
  })
}

///|
fn reply_remote_access(reply : @js.Value) -> RemoteAccess? {
  let json = @json.parse(@interop.reply_json_text(reply)) catch {
    _ => return None
  }
  guard json is Object(fields) else { return None }
  decode_remote_access(fields)
}

///|
/// Seed (or refresh) the mirror. A failed or malformed reply leaves the
/// current mirror in place — `auth.changed` corrects it on the next move.
fn fetch_remote_status(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        Local,
        "auth.status",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      if reply_remote_access(reply) is Some(status) {
        scheduler.add(dispatch(RemoteStatusLoaded(status)))
      }
    })
  })
}

///|
/// Run the loopback sign-in. The reply arrives only after the user's
/// browser round-trip, minutes later at the worst — the section shows an
/// in-progress state the whole while.
fn connect_remote(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        Local,
        "auth.connect",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(RemoteConnectFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      match reply_remote_access(reply) {
        Some(status) => scheduler.add(dispatch(RemoteConnectFinished(status)))
        None =>
          scheduler.add(dispatch(RemoteConnectFailed("malformed auth reply")))
      }
    })
  })
}

///|
/// Abort a waiting sign-in. The connect's own failure reply settles the
/// section, so this only surfaces its *own* failure (a dead bridge).
fn cancel_remote(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ = @interop.bridge_request(
        Local,
        "auth.cancel",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(RemoteDisconnectFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
    })
  })
}

///|
/// Sign out. Success comes back as the post-sign-out status.
fn disconnect_remote(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        Local,
        "auth.disconnect",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(RemoteDisconnectFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      match reply_remote_access(reply) {
        Some(status) => scheduler.add(dispatch(RemoteStatusLoaded(status)))
        None =>
          scheduler.add(
            dispatch(RemoteDisconnectFailed("malformed auth reply")),
          )
      }
    })
  })
}
