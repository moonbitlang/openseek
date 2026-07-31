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
    // Proton runs everything in one process; the executable path locates the
    // bundled frontend assets and the engine binary that ship alongside it.
    let executable = match @env.args().get(0) {
      Some(command) => command
      None => abort("current executable command is unavailable")
    }
    let log = launch_logger()
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
    log.info() <? { "message": "host process start" }
    log.info() <? { "message": "frontend entry", "path": frontend_entry }
    log.info() <? { "message": "engine", "path": engine }
    let runtime_dir = @host.prepared_runtime_dir()
    // The relay sign-in store: a persisted session from auth.json, unless the
    // environment override pins the connector config directly (development).
    let auth = @auth.AuthStore::load(
      runtime_dir?,
      env_override?=relay_settings(),
    )
    let state = @api.ApiState::new(engine~, runtime_dir?, executable~, auth~)
    let bridge = @extension.DesktopBridgeActor::new(state)
    let relay = @remote.RelayActor::new(state, announce=device => {
      log.info() <? { "message": "relay registered", "device": device }
    })
    // Proton exposes the `__MoonBit__` bridge — both the ops and the event
    // channel the frontend listens on — only to the `proton://app/` origin its
    // asset entry serves from. The window is bridge-only: it makes no HTTP
    // requests at all (a proton:// page's http fetches stall inside CEF's
    // network service). Remote browsers use the same method catalog over the
    // relay WebSocket instead (docs/remote-protocol.md).
    let app = @proton.asset(
        "OpenSeek Desktop",
        frontend_entry,
        width=1120,
        height=760,
      )
      .debug_level(1)
      .extension(@extension.openseek_extension(state, bridge))
      // System notifications are an ordinary generated extension now: the
      // frontend posts them and receives `notification.click` with the run id.
      .extension(@notification.extension())
      // The connect request proves the page can issue commands; this paired
      // lifecycle supplies the window-owned event destination that remains
      // valid after that request returns.
      .window_lifecycle(
        on_ready=async fn(context) { bridge.window_ready(context.events()) },
        on_close=async fn(_) { bridge.window_closed() },
      )
    @async.with_task_group(group => {
      // The bridge actor, engine actor, and host actors run for the app's
      // lifetime — they feed every page/client rather than borrowing a
      // `host.connect` request task as their owner.
      group.spawn_bg(allow_failure=true, () => bridge.run())
      group.spawn_bg(allow_failure=true, () => {
        state
        .engine_actor()
        .run(state.sink(), message => {
          state.publish("agent.error", { "message": Json::string(message) })
        })
      })
      @host.spawn_host_pumps(group, state.host_state(), (method_, params) => {
        state.publish(method_, params)
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
