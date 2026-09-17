///|
async fn main {
  // A command line this host does not understand is a usage error like any
  // CLI's, and it ends the launch — Proton itself starts the binary with no
  // arguments, so only a person can get here.
  let matches = command.parse(argv=@env.args()[1:], env=@env.get_env_vars())
  // Hidden probe target: the login-shell environment probe re-execs this
  // binary through the user's shell; print the marker-wrapped JSON
  // environment and quit before any logging or CEF setup.
  if matches.values.get("print-env-json") is Some([mark, ..]) {
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
  // process before anything downstream — engine, LSP, mbtx snippets — spawns.
  @shellenv.apply_login_shell_env(executable)
  // The user's login shell supplies the base environment, then installed
  // tools take precedence. Both the OpenSeek engine and Codex app-server are
  // created below and therefore pass this packaged `rg` to agent tool calls.
  if @host.PackagedTools::resolve() is Some(tools) {
    tools.apply_to_process_env()
  }
  let frontend = @host.frontend_bundle()
  let engine = @engine.engine_command()
  // The window is an ordinary page against the host's own loopback origin:
  // the frontend bundle over `http://127.0.0.1:<port>/` and one JSON-RPC
  // WebSocket — the same catalog, envelope, and client path a relay browser
  // gets (docs/remote-protocol.md). The port is fixed so the origin, and with
  // it the page's localStorage, survives relaunches; `--port` and
  // OPENSEEK_PORT override it. The launch token minted here is the
  // WebSocket's capability; it rides the entry URL's query string.
  let port = get_port(matches, app)
  guard @entropy.random_hex(32) is Some(token) else {
    // No OS entropy is a hard failure, never weak randomness.
    abort("no OS entropy available for the desktop transport token")
  }
  @xlog.info() <? { "message": "host process start" }
  @xlog.info() <?
    {
      "message": "frontend bundle",
      "root": frontend.root,
      "entry": frontend.entry,
    }
  @xlog.info() <? { "message": "engine", "path": engine }
  @xlog.info() <? { "message": "codex", "path": @codex.command() }
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
  let app_version = app.version() catch { _ => "development" }
  @xlog.info() <? { "message": "app version", "version": app_version }
  // The relay sign-in store: a persisted session from auth.json, unless the
  // environment override pins the connector config directly (development).
  let auth = @auth.AuthStore::load(
    runtime_dir?,
    env_override?=relay_settings(matches),
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
  // The dock's browser tabs: native web contents views, owned by the
  // window and commanded over window-only `browser.*` methods.
  let views = @window.BrowserViews()
  let relay = @remote.RelayActor(state, announce=device => {
    @xlog.info() <? { "message": "relay registered", "device": device }
  })
  // Bind before the window can navigate: the listener's backlog holds the
  // page's first requests until the accept loop starts with the actors.
  let local_server = @remote.LocalServer::start(
    state,
    root=frontend.root,
    entry=frontend.entry,
    token~,
    window_endpoints=@window.endpoints(state, views),
    // A reloaded page allocates browser ids from scratch; the previous
    // page's native views must not survive its attachment.
    on_page_attached=() => views.close_all(),
    port~,
  )
  @xlog.info() <?
    {
      "message": "loopback origin",
      "origin": local_server.origin(),
      "configured_port": port,
    }
  let app = app.entry_url(local_server.entry_url())
  // One host per identity: `single_instance` hands a later launch to the
  // process already holding that identity's lock, and that process brings its
  // window to the front. Off by default for now; see `single_instance_wanted`.
  let single_instance = single_instance_wanted(matches, app)
  let app = if single_instance { app.single_instance() } else { app }
  let app = app
    // Let the page palette paint the native titlebar area. The default macOS
    // titlebar follows the system appearance, so an explicit in-app dark theme
    // otherwise leaves a bright strip above the dark application shell.
    .titlebar_style(Overlay)
    // Give the macOS buttons a 16pt left inset and center their 14pt height in
    // the 46px app header (base.css). Proton reports the reserved titlebar area
    // so the sidebar toggle follows their position, including after zoom.
    .traffic_light_position(x=16, y=16)
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
        ignore(@window.open_external({ url: request.url, })) catch {
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
    // What stays on Proton's injected runtime are the things only it can do
    // for the page — both granted to the configured entry page, which is the
    // loopback origin now. System notifications: the frontend posts them and
    // receives `notification.click` with the run id. Native dialogs: the save
    // dialog `session.export` needs a window context for.
    .capability(@notification.capability())
    .capability(@window.dialogs_capability())
    // The window handle the browser views hang off.
    .window_lifecycle(
      on_ready=fn(context) { views.window_ready(context.handle()) },
      on_close=fn(_) { views.window_closed() },
    )
    // Geometry can change without a DOM fullscreen event (native fullscreen,
    // display scaling, or page zoom). The loopback delivery profile alone
    // forwards this to the page; a relay client never sees it.
    .on_window_event(fn(_, event) noraise {
      if event is StateChanged(_) {
        state.publish(WindowChromeChanged)
      }
    })
    // Browser view events reach the page as `browser.event` notifications;
    // views that are not browser tabs are not the frontend's business.
    .on_view_event(fn(view, event) noraise {
      match @window.browser_view_id(view.id()) {
        Some(id) =>
          if @window.view_event_json(id, event) is Some(payload) {
            state.publish(BrowserEvent(payload))
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
    // page/client rather than borrowing a request task as their owner — and
    // stop when the run loop returns. The loopback server owns the window's
    // origin for the same span.
    let app = app.app_lifecycle(
      on_start=async fn(_) {
        is_primary = true
        prepare_workspaces()
        group.spawn_bg(allow_failure=true, () => local_server.run())
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
        group.spawn_bg(allow_failure=true, () => state.run_schedules())
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
          "SeekMoon is already running; its window was brought to the front. Quit it first, or start this one without --single-instance.",
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
/// The application as the project config describes it: identity, product
/// name, and package version. A development build never answers to the
/// shipped identity: `package/build.mjs` generates a project config carrying
/// its own, and `proton dev` hands that config on to the host through
/// PROTON_PROJECT_CONFIG, so `load_config` picks it up either way. The entry
/// URL is a placeholder until `main` knows the loopback port.
let app : @proton.App = @proton.url(
  "SeekMoon",
  "http://127.0.0.1/",
  width=1120,
  height=760,
).load_config()

///|
/// The host's command line. Proton launches the binary with no arguments, so
/// every option also reads an environment variable — the way a packaged app
/// is usually configured. The functions below each pull one setting out of
/// the parsed `Matches`.
let command : @argparse.Command = Command(
  "seekmoon",
  about="The SeekMoon desktop host.",
  options=[
    OptionArg(
      "port",
      long="port",
      env="OPENSEEK_PORT",
      about="The loopback port the window's origin uses. Release builds default to 27182, development builds to 27183.",
    ),
    OptionArg(
      "relay-url",
      long="relay-url",
      env="OPENSEEK_RELAY_URL",
      about="Development override: the relay's /v1/tunnel WebSocket URL. Together with --device-token it bypasses sign-in.",
    ),
    OptionArg(
      "device-token",
      long="device-token",
      env="OPENSEEK_DEVICE_TOKEN",
      about="Development override: the secret that keeps this machine's device id stable at the relay.",
    ),
    OptionArg(
      "device-name",
      long="device-name",
      env="OPENSEEK_DEVICE_NAME",
      default_values=["desktop"],
      about="How the relay's status page labels this device under the development override.",
    ),
    // The login-shell environment probe re-execs this binary through the
    // user's shell and reads the marker-wrapped JSON environment back.
    OptionArg("print-env-json", long="print-env-json", hidden=true),
  ],
  flags=[
    FlagArg(
      "single-instance",
      long="single-instance",
      env="OPENSEEK_DESKTOP_SINGLE_INSTANCE",
      about="Hand this launch to a release build already running under the same identity, bringing its window to the front. Off by default: a host Proton leaves stuck in cef_shutdown would otherwise capture every later launch.",
    ),
  ],
)

///|
/// The loopback port this launch listens on: `--port` / OPENSEEK_PORT when
/// given, otherwise the build's fixed default — the release port, or the
/// development port under the `.dev` identity. A value that is not a number
/// is logged, never refused: a stray OPENSEEK_PORT in someone's shell must
/// not keep the app from starting.
fn get_port(
  matches : @argparse.Matches,
  app : @proton.App,
) -> Int raise @proton.AppPathError {
  let default = if is_development_build(app) {
    DevelopmentPort
  } else {
    ReleasePort
  }
  guard matches.values.get("port") is Some([value, ..]) else { return default }
  @string.parse_int(value, base=10) catch {
    _ => {
      @xlog.warn() <?
        {
          "event": "desktop_port_ignored",
          "value": value,
          "port": default,
          "message": "--port / OPENSEEK_PORT is not a number; using the default port",
        }
      default
    }
  }
}

///|
/// The fixed loopback port behind the window's origin. A release build
/// and a development build both run on this machine and must
/// not fight over one port — a development build that lost that fight would
/// land on an ephemeral origin and lose its preferences on every launch —
/// so each has its own default. `--port` / OPENSEEK_PORT override either.
const ReleasePort = 27182

///|
const DevelopmentPort = 27183

///|
/// The identity suffix `package/build.mjs` appends when it generates the
/// project config a development build runs under. Spelled there too; this is
/// the shared half of that convention.
const DevelopmentSuffix = ".dev"

///|
/// Whether the loaded project config carries the development identity — a
/// `package/macos` build without `--release` as much as an unbundled
/// `package/dev` run. Proton offers no getter for the identifier it loaded;
/// it comes back through `data_dir`, whose last segment it is, and a path
/// separator cannot appear inside an identity, so a data directory ending in
/// the suffix is one whose identity does. An identity that cannot be
/// resolved fails the launch: the port and single instance both hang off it,
/// and guessing would move a real install's origin.
fn is_development_build(app : @proton.App) -> Bool raise @proton.AppPathError {
  app.data_dir().has_suffix(DevelopmentSuffix)
}

///|
/// Whether this launch takes part in single instance.
///
/// Off unless `--single-instance` (OPENSEEK_DESKTOP_SINGLE_INSTANCE=1) says
/// so: a host that Proton
/// leaves stuck in `cef_shutdown` keeps the identity's lock, and every later
/// launch would hand itself to it. Even then only the shipped application
/// takes part; a development build must start beside the binary it replaced.
fn single_instance_wanted(
  matches : @argparse.Matches,
  app : @proton.App,
) -> Bool raise @proton.AppPathError {
  matches.flags.get("single-instance") is Some(true) &&
  !is_development_build(app)
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
fn relay_settings(matches : @argparse.Matches) -> @auth.ConnectorConfig? {
  guard matches.values.get("relay-url") is Some([relay_url, ..]) &&
    matches.values.get("device-token") is Some([device_token, ..]) &&
    matches.values.get("device-name") is Some([device_name, ..]) else {
    return None
  }
  Some({ relay_url, device_token, device_name, })
}
