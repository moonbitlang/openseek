///|
fn main {
  // Hidden probe target: the login-shell environment probe re-execs this
  // binary through the user's shell; print the marker-wrapped JSON
  // environment and quit before any logging or CEF setup.
  if @env.args() is [_, "--print-env-json", mark, ..] {
    @shellenv.print_env_json(mark)
    return
  }
  // The process main thread owns AppKit and CEF. Proton runs this async body
  // on its application thread and marshals UI work back to the main thread,
  // so native shutdown cannot race a still-open browser window.
  @proton.run(() => {
    // Proton runs everything in one process; the executable path locates the
    // bundled frontend assets and the engine binary that ship alongside it.
    let executable = match @env.args().get(0) {
      Some(command) => command
      None => abort("current executable command is unavailable")
    }
    let log = launch_logger()
    log.info() <? { "message": "start" }
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
    let state = @api.ApiState::new(engine~, runtime_dir?, executable~)
    let bridge = @extension.DesktopBridgeActor::new(state)
    // Proton exposes the `__MoonBit__` bridge — both the ops and the extension
    // event channel the frontend listens on — from its `proton://app/` asset
    // origin. Proton reads the entry document and serves sibling static assets
    // such as frontend.js and viewer.css from that same directory.
    let app = @proton.asset(
        "OpenSeek Desktop",
        frontend_entry,
        width=1120,
        height=760,
      )
      .debug_level(1)
      .extension(
        @proton_extension.from_command_spec(
          @extension.openseek_extension(state, bridge),
        ),
      )
      // Notifications are an ordinary generated extension: the frontend
      // posts them and receives `notification.click` with the run id.
      .extension(@notification.extension())
    @async.with_task_group(group => {
      // These actors own their queues and native resources for the whole app
      // lifetime. A bridge request only posts work; closing the app cancels
      // the actors together after Proton has returned from its run loop.
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
      // Remote access stays opt-in in this infrastructure PR. Product
      // sign-in and settings UI belong to the frontend follow-up.
      if relay_settings() is Some((relay_url, device_token, device_name)) {
        let relay = @remote.RelayActor::new(
          state,
          relay_url~,
          device_token~,
          device_name~,
          announce=device => {
            log.info() <? { "message": "relay registered", "device": device }
          },
        )
        group.spawn_bg(allow_failure=true, () => relay.run())
      }
      try {
        app.run()
        log.info() <? { "message": "host process exit ok" }
      } catch {
        error =>
          log.error() <?
            {
              "message": "host process error",
              "error": @debug.render(Repr(error)),
            }
      }
      group.return_immediately(())
    })
    // A successful `apply_update` swapped the bundle on disk and left a
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
  })
}

///|
/// Fixed relay settings for development and protocol testing. Both the relay
/// URL and token are required; the later product-UI change replaces this
/// environment-only entry point with persisted sign-in state.
fn relay_settings() -> (String, String, String)? {
  guard @envx.get("OPENSEEK_RELAY_URL") is Some(relay_url) &&
    @envx.get("OPENSEEK_DEVICE_TOKEN") is Some(device_token) else {
    return None
  }
  let device_name = match @envx.get("OPENSEEK_DEVICE_NAME") {
    Some(name) => name
    None => "desktop"
  }
  Some((relay_url, device_token, device_name))
}
