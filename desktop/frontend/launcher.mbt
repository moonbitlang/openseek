// The topbar app launcher's commands: probe the host for installed apps and
// ask it to open one on the active conversation's workspace. Both are plain
// request/reply calls on the engine-host bridge.

///|
/// Fetch the apps the host detects as installed. Replies retain `channel`, so
/// changing focus while the request is in flight cannot replace the new
/// device's launcher cache.
fn fetch_apps(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        "app.list",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              LauncherFailed(
                channel~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      match @transcript.decode_apps_reply(@interop.reply_json_text(reply)) {
        Some(apps) => scheduler.add(dispatch(LauncherLoaded(channel~, apps~)))
        None =>
          scheduler.add(
            dispatch(LauncherFailed(channel~, message="malformed app list")),
          )
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
  channel : @interop.ChannelId,
  session : String,
  cwd~ : @pathx.Absolute?,
  app : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      @interop.set_trimmed(payload, "cwd", workspace_token(cwd))
      payload["app"] = app
      let _ : @js.Value = @interop.bridge_request(
        channel,
        "app.launch",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(HostActionFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
    })
  })
}

///|
test "launcher replies stay scoped to the device that requested them" {
  let dispatch = test_dispatch()
  let first : @interop.ChannelId = Remote("d_a")
  let second : @interop.ChannelId = Remote("d_b")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(first), bridge: Connected },
      { ..empty_device_state(second), bridge: Connected },
    ],
    focused: first,
  }
  let (_, first_open) = update(dispatch, ToggleLauncher, model)
  assert_true(first_open.launcher.channel == Some(first))
  let (_, first_loaded) = update(
    dispatch,
    LauncherLoaded(channel=first, apps=[{ id: "a", name: "A", icon: "" }]),
    first_open,
  )
  assert_true(first_loaded.launcher.apps is AppsFetched([_]))
  let (_, refocused) = focus_channel(dispatch, first_loaded, second)
  assert_true(refocused.launcher.channel is None)
  assert_true(refocused.launcher.apps is AppsNotFetched)
  let (_, second_open) = update(dispatch, ToggleLauncher, refocused)
  assert_true(second_open.launcher.channel == Some(second))
  let (_, stale) = update(
    dispatch,
    LauncherLoaded(channel=first, apps=[
      { id: "stale", name: "Stale", icon: "" },
    ]),
    second_open,
  )
  assert_true(stale.launcher.apps is AppsNotFetched)
  let (_, current) = update(
    dispatch,
    LauncherLoaded(channel=second, apps=[{ id: "b", name: "B", icon: "" }]),
    stale,
  )
  guard current.launcher.apps is AppsFetched(apps) else {
    fail("current device's apps were not accepted")
  }
  inspect(apps[0].id, content="b")
}
