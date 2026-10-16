// The native host's presentation-only remote-access mirror. Account sign-in
// and the independent device toggle share Settings; credentials are retrieved
// only through this window's account.session endpoint. These operations never
// target a focused remote computer. auth.changed refreshes the status mirror.

///|
/// Project the shared auth status used by both replies and broadcasts.
fn RemoteAccess::from_status(
  payload : @protocol.AuthStatusPayload,
) -> RemoteAccess {
  {
    connected: payload.connected,
    managed_by_env: payload.managed_by_env.unwrap_or(false),
    device_url: payload.device.map(device => device.url),
  }
}

///|
/// Seed (or refresh) the mirror. A failed or malformed reply leaves the
/// current mirror in place — `auth.changed` corrects it on the next move.
fn fetch_remote_status(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let status = @interop.bridge_request(
        Local,
        @commands.auth_status,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(RemoteStatusLoaded(RemoteAccess::from_status(status))),
      )
    })
    |> ignore
  })
}

///|
/// Run the loopback sign-in. The reply arrives only after the user's
/// browser round-trip, minutes later at the worst — the section shows an
/// in-progress state the whole while.
fn connect_remote(dispatch : @cmd.Emit[Msg], epoch : Int32) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request(
        Local,
        @commands.auth_connect,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              AccountLoaded(epoch, Err(@interop.bridge_error_text(error))),
            ),
          )
          return
        }
      }
      scheduler.add(fetch_account(dispatch, true, epoch))
    })
    |> ignore
  })
}

///|
/// Abort a waiting sign-in. The connect's own failure reply settles the
/// section, so this only surfaces its *own* failure (a dead bridge).
fn cancel_remote(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request(
        Local,
        @commands.auth_cancel,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(RemoteDisconnectFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
    })
    |> ignore
  })
}

///|
/// Sign out. Success comes back as the post-sign-out status.
fn disconnect_remote(dispatch : @cmd.Emit[Msg], epoch : Int32) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request(
        Local,
        @commands.auth_disconnect,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              AccountLoaded(epoch, Err(@interop.bridge_error_text(error))),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(AccountLoaded(epoch, Ok(None))))
    })
    |> ignore
  })
}

///|
fn set_remote_access(dispatch : @cmd.Emit[Msg], enabled : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let status = @interop.bridge_request(Local, @commands.remote_access_set, @protocol.RemoteAccessPayload::{
        enabled,
      }) catch {
        error => {
          scheduler.add(
            dispatch(RemoteDisconnectFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(RemoteStatusLoaded(RemoteAccess::from_status(status))),
      )
    })
    |> ignore
  })
}
