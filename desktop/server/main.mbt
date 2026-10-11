// The desktop backend without a window: the same API state, engine and
// Codex supervisors, schedules, and host pumps the Proton host runs, served
// over the console listener instead of the window bridge. Nothing in this
// module depends on Proton, so it builds on a machine with no window toolkit
// and runs headless — a container, a virtual machine, a remote box.

///|
async fn main {
  let matches = command.parse(argv=@env.args()[1:], env=@env.get_env_vars())
  guard matches.values.get("resource-dir") is Some([resource_dir, ..]) else {
    fail("--resource-dir (OPENSEEK_DESKTOP_RESOURCE_DIR) is required")
  }
  guard matches.values.get("port") is Some([port, ..]) else {
    fail("--port has no value")
  }
  let port = @string.parse_int(port)
  // No window toolkit answers where this host's files are, so the launcher
  // says: the package root holding `seekmoon/`, or a checkout's `desktop/`.
  let resources : @resources.Resources = {
    dir: @pathx.Path(resource_dir).resolve().to_path(),
    packaged: matches.flags.get("packaged") is Some(true),
  }
  let executable = match @env.args() {
    [executable, ..] => Some(executable)
    [] => None
  }
  if @host.PackagedTools::resolve(Some(resources)) is Some(tools) {
    tools.apply_to_process_env()
  }
  let frontend_entry = @pathx.Path(@host.frontend_entry_path(resources))
  let engine = @engine.engine_command(resources)
  let runtime_dir = match executable {
    Some(executable) => @host.prepared_runtime_dir(executable)
    None => None
  }
  let codex_home = match runtime_dir {
    Some(dir) => @codex.prepared_home(dir)
    None => None
  }
  let codex = @codex.CodexSettings(command=@codex.command(), home=codex_home)
  // A headless process has no terminal to read: its standard output is a
  // pipe, which the C runtime buffers by the block, so log lines would sit
  // unseen until the buffer filled. The log goes to a file beside the rest of
  // the runtime state instead, as the window host's does.
  if runtime_dir is Some(dir) {
    let path = dir.join("openseek-server.log").to_string()
    @xlog.global().set_handler(@xlog.File(path))
  }
  // Like a development window host, the server persists no relay sign-in:
  // it may share the runtime directory with an installed application, and
  // one `auth.json` is one device token.
  let auth = @auth.AuthStore::load()
  let console = @remote.LocalConsole::bind(port~)
  let state = @api.ApiState(
    engine~,
    codex~,
    runtime_dir?,
    executable?,
    auth~,
    console_url=console.entry_url(),
    resources~,
  )
  let relay = @remote.RelayActor(state, announce=device => {
    @xlog.info() <? { "message": "relay registered", "device": device }
  })
  @async.with_task_group(group => {
    state.start_services(group)
    group.spawn_bg(allow_failure=true, () => relay.run())
    @xlog.info() <?
      {
        "event": "desktop_server_serving",
        "origin": console.origin(),
        "root": frontend_entry.dirname().to_string(),
        "engine": engine,
      }
    // The one line a person needs: the page to open, token included. Written
    // straight to the descriptor so it reaches a pipe or `docker logs` at
    // once instead of waiting in the runtime's output buffer.
    @stdio.stdout.write("\{console.entry_url()}\n")
    console.run(
      state,
      root=frontend_entry.dirname().to_string(),
      entry=frontend_entry.basename().to_owned(),
    )
  })
}

///|
/// The server's command line; each option also reads an environment
/// variable, the way a supervised process is usually configured.
let command : @argparse.Command = Command(
  "seekmoon-server",
  about="The SeekMoon desktop backend, served to a browser on loopback.",
  options=[
    OptionArg(
      "resource-dir",
      long="resource-dir",
      env="OPENSEEK_DESKTOP_RESOURCE_DIR",
      about="The directory this host's bundled files live under: a package root holding seekmoon/, or a checkout's desktop/.",
    ),
    OptionArg(
      "port",
      long="port",
      env="OPENSEEK_DESKTOP_SERVER_PORT",
      default_values=["27183"],
      about="The loopback port to serve the console on; an ephemeral port is used when it is taken.",
    ),
  ],
  flags=[
    FlagArg(
      "packaged",
      long="packaged",
      about="Read --resource-dir as an installed package root rather than a checkout's desktop/.",
    ),
  ],
)
