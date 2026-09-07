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
  // Proton runs everything in one process and supplies the same resource
  // directory abstraction on every packaged platform. The development
  // launcher exposes `desktop/` through the same abstraction.
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
  if @host.PackagedTools::resolve() is Some(tools) {
    tools.apply_to_process_env()
  }
  let frontend_entry = @host.frontend_entry_path()
  let engine = @engine.engine_command()
  let app = @proton.asset("SeekMoon", frontend_entry, width=1120, height=760)
  let app_version = app.version() catch { _ => "development" }
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
  // The identity this process answers to. A development build never answers
  // to the shipped one: `package/build.mjs` generates a project config
  // carrying its own, and `proton dev` hands that config on to the host
  // through PROTON_PROJECT_CONFIG, so this call picks it up either way.
  let app = app.load_config()
  // One host per identity, for the shipped application: `single_instance`
  // hands a later launch to the process already holding that identity's lock,
  // and that process brings its window to the front.
  let single_instance = single_instance_wanted(app)
  let app = if single_instance { app.single_instance() } else { app }
  let app = app
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
        ignore(@extension.open_external({ url: request.url, })) catch {
          error =>
            @xlog.error() <?
              {
                "event": "external_link_open_failed",
                "url": request.url,
                "error": @debug.render(Repr(error)),
              }
        }
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
        if @platform.apple_os_mac {
          @proton.Menu::role(Window, items=[
            @proton.MenuItem::role(Minimize),
            @proton.MenuItem::role(Zoom),
            @proton.MenuItem::command(
              @commands.CloseFocusedMenuCommand,
              "Close",
              key="w",
            ),
          ])
        } else {
          @proton.Menu::role(Window)
        },
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
    // Geometry can change without a DOM fullscreen event (native fullscreen,
    // display scaling, or page zoom). Only this window's page is notified.
    .on_window_event(async fn(_, event) noraise {
      if event is StateChanged(_) {
        bridge.notify_window_chrome_changed() catch {
          // Cancellation during shutdown leaves no page to notify.
          _ => ()
        }
      }
    })
    // Browser view events reach the page as `browser.event` notifications;
    // views that are not browser tabs are not the frontend's business.
    .on_view_event(async fn(view, event) noraise {
      match @extension.browser_view_id(view.id()) {
        Some(id) =>
          if @extension.view_event_json(id, event) is Some(payload) {
            bridge.notify_browser_event(payload) catch {
              // Only cancellation can interrupt the queue put — the app is
              // shutting down, so the event has nowhere to go anyway.
              _ => ()
            }
          }
        None => ()
      }
    })
  // Set by the application lifecycle hook, which only the process that kept
  // this launch reaches. A forwarded launch returns from
  // `app.run()` having done nothing, and must not go on to act on state
  // that belongs to the host still running.
  let mut is_primary = false
  @async.with_task_group(group => {
    // Everything that acts on state belonging to whoever owns the runtime
    // directory starts here and nowhere earlier: the hook runs only in the
    // process that kept the launch, and before its window opens. A launch
    // handed to another host returns from `app.run()` without ever reaching
    // it, so it neither spawns a Codex app-server or engine of its own, nor
    // registers with the relay under the running host's device identity.
    //
    // The actors run for the app's lifetime on this group — they feed every
    // page/client rather than borrowing a `host.connect` request task as
    // their owner — and stop when the run loop returns.
    let app = app.app_lifecycle(
      on_start=async fn(_) {
        is_primary = true
        prepare_workspaces()
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
        // The relay actor registers this host whenever a sign-in (or the
        // environment override) says so, and idles otherwise.
        group.spawn_bg(allow_failure=true, () => relay.run())
      },
      on_shutdown=fn(_) {  },
    )
    @xlog.info() <?
      { "event": "desktop_app_run_start", "single_instance": single_instance }
    try {
      app.run()
      if !is_primary {
        // Nothing else tells a `moon run` user what happened: Proton notes
        // the forwarding in its own log, the running instance's window comes
        // to the front, and this process ends.
        println(
          "SeekMoon is already running; its window was brought to the front. Quit it first, or set OPENSEEK_DESKTOP_MULTI_INSTANCE=1 to start another instance.",
        )
      }
      @xlog.info() <?
        {
          "event": "desktop_app_run_return",
          "result": "ok",
          "primary": is_primary,
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
  //
  // Only the host that ran the loop may take that marker. A forwarded
  // launch reaches here too, having done nothing, and taking the marker
  // there would consume the still-running primary's relaunch: the bundle
  // would reopen, hand itself straight back to that primary, exit — and
  // when the primary finally closed, its marker would be gone and the
  // update would never be entered. The nesting is deliberate; a `&&` chain
  // would take the marker while deciding whether it was allowed to.
  if is_primary {
    if runtime_dir is Some(dir) {
      if @update.take_relaunch_target(work_dir=dir.to_string()) is Some(target) {
        @xlog.info() <? { "message": "relaunch after update", "path": target }
        let code = @process.run("open", ["-n", target]) catch {
          error => {
            @xlog.error() <?
              { "message": "relaunch failed", "error": "\{error}" }
            return
          }
        }
        if code != 0 {
          @xlog.error() <? { "message": "relaunch failed", "code": code }
        }
      }
    }
  }
  @xlog.info() <? { "event": "desktop_main_return", "primary": is_primary }
}

///|
/// The identity suffix `package/build.mjs` appends when it generates the
/// project config a development build runs under. Spelled there too; this is
/// the shared half of that convention.
const DevelopmentSuffix = ".dev"

///|
/// Whether this launch takes part in single instance at all.
///
/// Only the shipped application does. A development build is a second copy of
/// the same program on the same machine, and being told "one is already
/// running" is never what its author wanted: a rebuilt one has to start, not
/// hand its launch to the binary it just replaced. Standing outside also
/// costs it nothing it had, since Proton only grants a persistent browser
/// profile to an application that owns a single-instance identity.
///
/// `OPENSEEK_DESKTOP_MULTI_INSTANCE` takes the shipped application out too,
/// for a harness driving several hosts or a second copy of one build.
///
/// The identity is read back through `data_dir`, whose last segment is the
/// identity Proton resolved from the manifest or the project config. Proton
/// has no public accessor for it, and reading it here rather than trusting
/// the build mode means the two always agree.
fn single_instance_wanted(app : @proton.App) -> Bool {
  if @envx.get("OPENSEEK_DESKTOP_MULTI_INSTANCE") is Some(_) {
    @xlog.info() <?
      {
        "event": "desktop_instance_opt_out",
        "message": "OPENSEEK_DESKTOP_MULTI_INSTANCE is set; starting beside any running host",
      }
    return false
  }
  let identity = app.data_dir() catch {
    error => {
      // Without an identity there is nothing to lock on, and guessing one
      // could silence a launch that belongs to the installed application.
      @xlog.warn() <?
        {
          "event": "desktop_instance_identity_unknown",
          "message": "could not resolve this application's identity; starting beside any running host",
          "error": @debug.render(Repr(error)),
        }
      return false
    }
  }
  // A path separator cannot appear inside an identity, so a data directory
  // ending in the suffix is one whose identity does.
  !identity.has_suffix(DevelopmentSuffix)
}

///|
/// First-launch and migration work on the workspace registry. The primary
/// runs this before it serves any client, so the first `workspace.list` a
/// page sees already reflects it.
async fn prepare_workspaces() -> Unit {
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
