///|
async fn main {
  // Hidden probe target: the login-shell environment probe re-execs this
  // binary through the user's shell; print the marker-wrapped JSON
  // environment and quit before any logging or CEF setup.
  if @env.args() is [_, "--print-env-json", mark, ..] {
    @shellenv.print_env_json(mark)
    return
  }
  // The async event loop on the process main thread drives Proton's native
  // loop directly (the external event loop is the only runner), so UI work
  // and shutdown ordering stay on the thread that owns AppKit and CEF.
  // Proton runs everything in one process. Packaged builds resolve copied
  // assets and the engine beside the executable; an unbundled Moon host
  // derives the frontend, engine, and state paths from its `_build` layout.
  let executable = match @env.args() {
    [command, ..] => command
    [] => abort("current executable command is unavailable")
  }
  launch_logger(executable)
  @xlog.info() <?
    {
      "event": "desktop_main_start",
      "message": "start",
      "log_path": @env.get_env_var("OPENSEEK_DESKTOP_LOG").unwrap_or(""),
    }
  // A Finder/Dock launch inherits only launchd's minimal environment; graft
  // the user's login-shell environment (PATH, custom variables) onto this
  // process before anything downstream — engine, LSP, shell tool — spawns.
  @shellenv.apply_login_shell_env(executable)
  // The user's login shell supplies the base environment, then installed
  // tools take precedence. Both the OpenSeek engine and Codex app-server are
  // created below and therefore pass this packaged `rg` to agent tool calls.
  if @host.PackagedTools::resolve(executable) is Some(tools) {
    tools.apply_to_process_env()
  }
  let frontend_entry = @host.frontend_entry_path(executable)
  let engine = @engine.engine_command(executable)
  let app_version = @host.package_version(executable)
  @xlog.info() <? { "message": "host process start" }
  @xlog.info() <? { "message": "frontend entry", "path": frontend_entry }
  @xlog.info() <? { "message": "engine", "path": engine }
  @xlog.info() <? { "message": "codex", "path": @codex.command() }
  @xlog.info() <? { "message": "app version", "version": app_version }
  let runtime_dir = @host.prepared_runtime_dir(executable)
  let codex_home = match runtime_dir {
    Some(dir) => @codex.prepared_home(dir)
    None => None
  }
  let codex = @codex.CodexSettings(command=@codex.command(), home=codex_home)
  @xlog.info() <?
    {
      "message": "codex home",
      "path": codex_home
      .map(p => p.to_string())
      .unwrap_or("(inherited environment)"),
    }
  // A fresh install has no workspaces at all. Attach the default one before
  // anything can serve a workspace list, so the first page to connect
  // already has somewhere to work. This runs exactly once per registry: a
  // user who later detaches it does not get it back.
  let default_workspace = @workspaces.initialize() catch {
    error => {
      // An unwritable Documents folder must not stop the app — the user can
      // still attach a project by hand.
      @xlog.error() <?
        {
          "message": "default workspace setup failed",
          "error": @debug.render(Repr(error)),
        }
      None
    }
  }
  if default_workspace is Some(dir) {
    @xlog.info() <?
      { "message": "default workspace attached", "path": dir.to_string() }
  }
  // Conversations the desktop used to keep in the global store predate
  // workspaces owning every record. Move them into the default workspace so
  // they stay listed; a failure leaves them where they are for a later launch.
  let migrated = @engine.migrate_global_store() catch {
    error => {
      @xlog.error() <?
        {
          "message": "global store migration failed",
          "error": @debug.render(Repr(error)),
        }
      0
    }
  }
  if migrated > 0 {
    @xlog.info() <?
      {
        "message": "migrated conversations from the global store",
        "count": migrated,
      }
  }
  // The relay sign-in store: a persisted session from auth.json, unless the
  // environment override pins the connector config directly (development).
  let auth = @auth.AuthStore::load(
    runtime_dir?,
    env_override?=relay_settings(),
    app_version~,
  )
  let state = @api.ApiState(
    engine~,
    codex~,
    runtime_dir?,
    executable~,
    auth~,
    app_version~,
  )
  let bridge = @extension.DesktopBridgeActor(state)
  // The dock's browser tabs: native web contents views, owned by the
  // window and commanded over bridge-local `browser.*` ops.
  let views = @extension.BrowserViews()
  let relay = @remote.RelayActor(state, announce=device => {
    @xlog.info() <? { "message": "relay registered", "device": device }
  })
  // Proton exposes the `__MoonBit__` bridge — both the ops and the event
  // channel the frontend listens on — only to the local origin its asset
  // entry serves from. The window is bridge-only: it makes no HTTP requests
  // at all. Remote browsers use the same method catalog over the relay
  // WebSocket instead (docs/remote-protocol.md).
  let app = @proton.asset("SeekMoon", frontend_entry, width=1120, height=760)
    .load_config()
    // Let the page palette paint the native titlebar area. The default macOS
    // titlebar follows the system appearance, so an explicit in-app dark theme
    // otherwise leaves a bright strip above the dark application shell.
    .titlebar_style(Overlay)
    .debug_level(1)
    // Rabbita consumes ordinary left-click navigation for the dock Browser,
    // but deliberately leaves Ctrl/Cmd-click and middle-click to Chromium.
    // Proton 0.2.6 reports those new-window requests here without their target
    // disposition, so `user_gesture` is temporarily the closest available
    // signal. This also includes a page calling `window.open` during a click;
    // deny the embedded window in every case, and send user-initiated URLs to
    // the system opener until Proton exposes the disposition.
    .on_new_window_request(async fn(_, request) noraise {
      if request.user_gesture {
        ignore(
          Some(@extension.open_external({ url: request.url, })) catch {
            error => {
              @xlog.error() <?
                {
                  "event": "external_link_open_failed",
                  "url": request.url,
                  "error": @debug.render(Repr(error)),
                }
              None
            }
          },
        )
      }
      Deny
    })
  // Proton auto-fills only the Application menu; Edit and Window must be
  // declared or macOS loses their key equivalents (Cmd+A/C/V/X/Z, Cmd+W/M),
  // which is what dispatches editing shortcuts to every text field. The
  // Windows engine has no native app menus and fails the run on any menu
  // bar, so the menu bar stays macOS/Linux-only.
  let app = if @platform.win32 || @platform.win64 {
    app
  } else {
    app.menu(
      MenuBar(menus=[
        @proton.Menu::role(Edit),
        Menu("Developer", items=[
          @proton.MenuItem::command(
            @commands.app_open_devtools.name(),
            "Open Developer Tools",
          ),
        ]),
        @proton.Menu::role(Window),
      ]),
    )
  }
  let app = app
    // Both command extensions are deliberately granted to the configured
    // entry page; registering backend handlers alone does not grant renderer
    // access.
    .capability(@extension.openseek_capability(state, bridge, views))
    // System notifications are an ordinary generated extension now: the
    // frontend posts them and receives `notification.click` with the run id.
    .capability(@notification.capability())
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
      .codex_actor()
      .run((method_, params) => {
        if @protocol.Notification::from_wire(method_, params)
          is Some(notification) {
          state.publish(notification)
        }
      })
    })
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
    @xlog.info() <? { "event": "desktop_app_run_start" }
    try {
      app.run()
      @xlog.info() <?
        {
          "event": "desktop_app_run_return",
          "result": "ok",
          "message": "host process exit ok",
        }
    } catch {
      error =>
        @xlog.error() <?
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
    @xlog.info() <? { "message": "relaunch after update", "path": target }
    let code = @process.run("open", ["-n", target]) catch {
      error => {
        @xlog.error() <? { "message": "relaunch failed", "error": "\{error}" }
        return
      }
    }
    if code != 0 {
      @xlog.error() <? { "message": "relaunch failed", "code": code }
    }
  }
  @xlog.info() <? { "event": "desktop_main_return" }
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
  Some({ relay_url, device_token, device_name, })
}
