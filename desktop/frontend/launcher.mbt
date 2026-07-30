// The topbar app launcher's commands: probe the host for installed apps and
// ask it to open one on the active conversation's workspace. Both are plain
// request/reply calls on the engine-host bridge.

///|
/// Fetch the apps detected by the desktop window's one Local native host.
/// `LauncherApps::AppsLoading` keeps this command single-flight.
fn fetch_apps(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        @interop.ChannelId::Local,
        "app.list",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(LauncherFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      match @transcript.decode_apps_reply(@interop.reply_json_text(reply)) {
        Some(apps) => scheduler.add(dispatch(LauncherLoaded(apps)))
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
        @interop.ChannelId::Local,
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
test "launcher catalog is host-global and loads single-flight" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, ToggleLauncher, test_model())
  assert_true(loading.launcher.open)
  assert_true(loading.launcher.apps is AppsLoading)
  // Closing and reopening while the probe is in flight preserves Loading,
  // so ToggleLauncher cannot schedule a second app.list command.
  let (_, closed) = update(dispatch, ToggleLauncher, loading)
  assert_false(closed.launcher.open)
  assert_true(closed.launcher.apps is AppsLoading)
  let (_, reopened) = update(dispatch, ToggleLauncher, closed)
  assert_true(reopened.launcher.open)
  assert_true(reopened.launcher.apps is AppsLoading)
  let (_, loaded) = update(
    dispatch,
    LauncherLoaded([{ id: "a", name: "A", icon: "" }]),
    reopened,
  )
  guard loaded.launcher.apps is AppsFetched(apps) else {
    fail("the Local host catalog was not accepted")
  }
  inspect(apps[0].id, content="a")
  // Once the single outstanding request settled, a delayed duplicate cannot
  // replace the host-global catalog.
  let (_, stale) = update(
    dispatch,
    LauncherLoaded([{ id: "stale", name: "Stale", icon: "" }]),
    loaded,
  )
  guard stale.launcher.apps is AppsFetched(apps) else {
    fail("the settled catalog was lost")
  }
  inspect(apps[0].id, content="a")
}

///|
test "a failed launcher probe retries on the next open" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, ToggleLauncher, test_model())
  let (_, failed) = update(dispatch, LauncherFailed("boom"), loading)
  assert_true(failed.launcher.apps is AppsFailed("boom"))
  let (_, closed) = update(dispatch, ToggleLauncher, failed)
  assert_true(closed.launcher.apps is AppsFailed("boom"))
  let (_, retrying) = update(dispatch, ToggleLauncher, closed)
  assert_true(retrying.launcher.open)
  assert_true(retrying.launcher.apps is AppsLoading)
}
