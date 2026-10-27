// Deliberate exports with no consumer inside the root workspace (see
// shrink_package.md). `moon ide analyze` counts only uses from the packages of
// the workspace it runs in, and every block below is used by `desktop/app`:
// the window host, module `openseek_desktop/app`, which builds in its own
// `desktop/app/moon.work` and so is invisible to the analyzer. It binds and
// serves the development console (`LocalConsole`) and constructs and runs the
// relay actor (`RelayActor`).

///|
/// Bind the loopback listener on `port`. When that port is taken (another
/// development host, an unrelated program), a fresh ephemeral port keeps the
/// console usable; the Settings page shows whichever origin was bound.
///
/// Exported for `desktop/app`, which binds the console in a development build.
pub async fn LocalConsole::bind(port~ : Int32) -> LocalConsole {
  guard @entropy.random_hex(32) is Some(token) else {
    // No OS entropy is a hard failure, never weak randomness.
    raise @host.HostError("no OS entropy available for the console token")
  }
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  ) catch {
    error => {
      @xlog.warn(category="transport") <?
        {
          "event": "console_port_unavailable",
          "port": port,
          "error": "\{error}",
          "message": "the development console port is taken; this launch serves the console on an ephemeral port",
        }
      Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
    }
  }
  let name = match @platform.machine_hostname() {
    Some(hostname) => hostname
    None => "This device"
  }
  {
    server,
    token,
    cookie_name: "seekmoon_session_\{server.addr.port()}",
    name,
  }
}

///|
/// The console's origin, which is also the only `Origin` its routes accept.
///
/// Exported for `desktop/app`, which logs the origin it serves the console on.
pub fn LocalConsole::origin(self : LocalConsole) -> String {
  "http://127.0.0.1:\{self.port()}"
}

///|
/// The URL a browser opens: the console page pinned to this host, with the
/// token that makes its document response set the session cookie.
///
/// Exported for `desktop/app`, which hands it to the API state as the
/// Settings page's console URL.
pub fn LocalConsole::entry_url(self : LocalConsole) -> String {
  "\{self.origin()}/?device=\{LocalConsoleDevice}&token=\{self.token}"
}

///|
/// Accept and serve connections for the app's lifetime. Files come from
/// `root`, with `/` resolving to `entry` inside it — the directory and
/// document the window itself loads. Each connection is its own task: a
/// static fetch answers one request and closes, while an upgraded WebSocket
/// lives as one client actor until the page goes away.
///
/// Exported for `desktop/app`, which spawns it once the app starts.
pub async fn LocalConsole::run(
  self : LocalConsole,
  state : @api.ApiState,
  root~ : String,
  entry~ : String,
) -> Unit {
  defer self.server.close()
  @async.with_task_group(group => {
    for ;; {
      let (conn, _) = self.server.accept()
      group.spawn_bg(allow_failure=true, () => {
        self.handle(state, conn, root~, entry~)
      })
    }
  })
}

///|
/// Build the app-lifetime owner of the relay control connection.
///
/// Exported for `desktop/app`, which constructs it at startup.
pub fn RelayActor::RelayActor(
  state : @api.ApiState,
  announce~ : (String) -> Unit,
) -> RelayActor {
  { state, announce, }
}

///|
/// Run for the host's lifetime (spawned once from main). `announce` preserves
/// the startup log line on every successful registration.
///
/// Exported for `desktop/app`, which spawns it beside the other services.
pub async fn RelayActor::run(self : RelayActor) -> Unit {
  let store = self.state.auth_store()
  for ;; {
    match store.desired_connector() {
      // Idle: nothing to run until someone pokes the store.
      None => store.wakeups().get()
      Some(config) => {
        let end : SessionEnd = @async.any([
          () => {
            store.wakeups().get()
            Poked
          },
          () => Refused(self.run_connector(config)),
        ])
        match end {
          // The config changed: `any` already cancelled the old connector
          // (tearing its control socket down); re-read and start over.
          Poked => ()
          Refused(message) => {
            @xlog.warn(category="remote") <?
              { "message": "relay refused registration", "error": message }
            store.handle_refusal(expected=config) catch {
              error =>
                // The relay already rejected this token. Keep the actor
                // alive and parked on the cleared in-memory state even if
                // persisting its signed-out marker failed.
                @xlog.warn(category="remote") <?
                  {
                    "message": "could not persist refused sign-out",
                    "error": "\{error}",
                  }
            }
            self.state.publish(AuthChanged(auth_changed_params(self.state)))
          }
        }
      }
    }
  }
}
