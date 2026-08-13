///|
fn main {
  // Hidden probe target: the login-shell environment probe re-execs this
  // binary through the user's shell; print the marker-wrapped JSON
  // environment and quit before any logging or CEF setup.
  if @env.args() is [_, "--print-env-json", mark, ..] {
    @shellenv.print_env_json(mark)
    return
  }
  // The process main thread now owns AppKit and CEF. Proton runs this async
  // body on its application thread and marshals UI work back to the main
  // thread, so native shutdown cannot race a still-open browser window.
  @proton.run(() => {
    // Proton runs everything in one process. Packaged builds resolve copied
    // assets and the engine beside the executable; an unbundled Moon host
    // derives the frontend, engine, and state paths from its `_build` layout.
    let executable = match @env.args() {
      [command, ..] => command
      [] => abort("current executable command is unavailable")
    }
    let log = launch_logger(executable)
    log.info() <?
      {
        "event": "desktop_main_start",
        "message": "start",
        "log_path": @env.get_env_var("OPENSEEK_DESKTOP_LOG").unwrap_or(""),
      }
    // A Finder/Dock launch inherits only launchd's minimal environment; graft
    // the user's login-shell environment (PATH, custom variables) onto this
    // process before anything downstream — engine, LSP, shell tool — spawns.
    @shellenv.apply_login_shell_env(executable, log)
    let frontend_entry = @host.frontend_entry_path(executable)
    let engine = @engine.engine_command(executable)
    let app_version = @host.package_version(executable)
    log.info() <? { "message": "host process start" }
    log.info() <? { "message": "frontend entry", "path": frontend_entry }
    log.info() <? { "message": "engine", "path": engine }
    log.info() <? { "message": "app version", "version": app_version }
    let runtime_dir = @host.prepared_runtime_dir(executable)
    // The relay sign-in store: a persisted session from auth.json, unless the
    // environment override pins the connector config directly (development).
    let auth = @auth.AuthStore::load(
      runtime_dir?,
      env_override?=relay_settings(),
      app_version~,
    )
    let state = @api.ApiState::new(
      engine~,
      runtime_dir?,
      executable~,
      auth~,
      app_version~,
    )
    let bridge = @extension.DesktopBridgeActor::new(state)
    // The dock's browser tabs: native web contents views, owned by the
    // window and commanded over bridge-local `browser.*` ops.
    let views = @extension.BrowserViews::new()
    let relay = @remote.RelayActor::new(state, announce=device => {
      log.info() <? { "message": "relay registered", "device": device }
    })
    // Proton exposes the `__MoonBit__` bridge — both the ops and the event
    // channel the frontend listens on — only to the local origin its asset
    // entry serves from. The window is bridge-only: it makes no HTTP requests
    // at all. Remote browsers use the same method catalog over the relay
    // WebSocket instead (docs/remote-protocol.md).
    let app = @proton.asset("SeekMoon", frontend_entry, width=1120, height=760).debug_level(
      1,
    )
    // Proton keeps its standard App/Edit/Window menus around custom menus,
    // so adding Developer does not remove native editing shortcuts. The
    // Windows engine has no native app menus and fails the run on any menu
    // bar, so the Developer menu stays macOS/Linux-only.
    let app = if @platform.win32 || @platform.win64 {
      app
    } else {
      app.menu(
        @proton.MenuBar::new(menus=[
          @proton.Menu::new("Developer", items=[
            @proton.MenuItem::command(
              @commands.app_open_devtools.name(),
              "Open Developer Tools",
            ),
          ]),
        ]),
      )
    }
    let app = app
      // Both command extensions are deliberately exposed to the configured
      // entry page; registration alone does not grant renderer access.
      .expose(@extension.openseek_extension(state, bridge, views))
      // System notifications are an ordinary generated extension now: the
      // frontend posts them and receives `notification.click` with the run id.
      .expose(@notification.extension())
      // The connect request proves the page can issue commands; this paired
      // lifecycle supplies the window-owned event destination that remains
      // valid after that request returns — and the window handle the browser
      // views hang off.
      .window_lifecycle(
        on_ready=async fn(context) {
          views.window_ready(context.handle())
          bridge.window_ready(context.events())
        },
        on_close=async fn(_) {
          views.window_closed()
          bridge.window_closed()
        },
      )
      // Browser view events reach the page as `browser.event` notifications;
      // views that are not browser tabs are not the frontend's business.
      .on_view_event(async fn(view, event) noraise {
        match @extension.browser_view_id(view.id()) {
          Some(id) =>
            bridge.notify_browser_event(@extension.view_event_json(id, event)) catch {
              // Only cancellation can interrupt the queue put — the app is
              // shutting down, so the event has nowhere to go anyway.
              _ => ()
            }
          None => ()
        }
      })
    @async.with_task_group(group => {
      // The bridge actor, engine actor, and host actors run for the app's
      // lifetime — they feed every page/client rather than borrowing a
      // `host.connect` request task as their owner.
      group.spawn_bg(allow_failure=true, () => bridge.run())
      group.spawn_bg(allow_failure=true, () => {
        state
        .engine_actor()
        .run(state.sink(), message => {
          state.publish(
            AgentError({
              run_id: None,
              message: Some(message),
              exit_code: None,
              diagnostics: None,
            }),
          )
        })
      })
      @host.spawn_host_pumps(group, state.host_state(), notification => {
        state.publish(notification)
      })
      // The relay actor runs for the app's lifetime: it registers
      // this host whenever a sign-in (or the environment override) says so,
      // and idles otherwise.
      group.spawn_bg(allow_failure=true, () => relay.run())
      log.info() <? { "event": "desktop_app_run_start" }
      try {
        app.run()
        log.info() <?
          {
            "event": "desktop_app_run_return",
            "result": "ok",
            "message": "host process exit ok",
          }
      } catch {
        error =>
          log.error() <?
            {
              "event": "desktop_app_run_return",
              "result": "error",
              "message": "host process error",
              "error": @debug.render(Repr(error)),
            }
      }
      // The window is closed: tear the pumps (and with them every serve
      // engine) down rather than wait on their tasks forever.
      group.return_immediately(())
    })
    // A successful `update.apply` swapped the bundle on disk and left a
    // relaunch marker: reopen the new version now that the run loop is done.
    // `open -n` hands the launch to LaunchServices, so the new instance is
    // not our child and this process can exit right after.
    if runtime_dir is Some(dir) &&
      @update.take_relaunch_target(work_dir=dir.to_string()) is Some(target) {
      log.info() <? { "message": "relaunch after update", "path": target }
      let code = @process.run("open", ["-n", target]) catch {
        error => {
          log.error() <? { "message": "relaunch failed", "error": "\{error}" }
          return
        }
      }
      if code != 0 {
        log.error() <? { "message": "relaunch failed", "code": code }
      }
    }
    log.info() <? { "event": "desktop_main_return" }
  })
}

///|
/// The development relay override, all-or-nothing from the environment:
/// `OPENSEEK_RELAY_URL` (the relay's `/v1/tunnel` WebSocket URL) and
/// `OPENSEEK_DEVICE_TOKEN` (the secret that keeps this machine's device id
/// stable); `OPENSEEK_DEVICE_NAME` labels the device on the relay's status
/// page and defaults to "desktop". When set it bypasses sign-in entirely.
fn relay_settings() -> @auth.ConnectorConfig? {
  guard @envx.get("OPENSEEK_RELAY_URL") is Some(relay_url) &&
    @envx.get("OPENSEEK_DEVICE_TOKEN") is Some(device_token) else {
    return None
  }
  let device_name = match @envx.get("OPENSEEK_DEVICE_NAME") {
    Some(name) => name
    None => "desktop"
  }
  Some({ relay_url, device_token, device_name })
}
