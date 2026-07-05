// The topbar app launcher's commands: probe the host for installed apps and
// ask it to open one on the active conversation's workspace. Both are plain
// request/reply calls on the engine-host bridge.

///|
/// Fetch the apps the host detects as installed. Settles into `LauncherLoaded`
/// on success or `LauncherFailed` on a bridge/decoding error.
fn fetch_apps(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = bridge_request("list_apps", @js.Object::new().to_value()) catch {
        error => {
          scheduler.add(dispatch(LauncherFailed(bridge_error_text(error))))
          return
        }
      }
      match @transcript.decode_apps_reply(reply_json_text(reply)) {
        Some(items) => scheduler.add(dispatch(LauncherLoaded(items)))
        None => scheduler.add(dispatch(LauncherFailed("malformed app list")))
      }
    })
  })
}

///|
/// Ask the host to open app `app` (an id from `list_apps`) on the
/// conversation's working directory — `cwd` when known, else derived by the
/// host from `session`. A failure pops an error toast.
fn launch_app(
  dispatch : @cmd.Emit[Msg],
  session : String,
  cwd : String,
  app : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["cwd"] = cwd
      payload["app"] = app
      let _ : @js.Value = bridge_request("launch_app", payload.to_value()) catch {
        error => {
          scheduler.add(dispatch(HostActionFailed(bridge_error_text(error))))
          return
        }
      }
    })
  })
}
