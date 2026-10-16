///|
let command : @argparse.Command = Command(
  "seekmoon-server",
  about="Serve the shared SeekMoon backend to terminal and desktop clients.",
  options=[
    OptionArg(
      "port",
      long="port",
      default_values=["27184"],
      about="Loopback port; 0 chooses a free port.",
    ),
    OptionArg(
      "engine",
      long="engine",
      default_values=["openseek"],
      about="OpenSeek engine executable.",
    ),
    OptionArg(
      "root",
      long="root",
      about="Directory containing the desktop browser frontend.",
    ),
    OptionArg(
      "entry",
      long="entry",
      default_values=["index.html"],
      about="Frontend document relative to --root.",
    ),
    OptionArg(
      "runtime-dir",
      long="runtime-dir",
      about="SeekMoon backend state directory.",
    ),
    OptionArg(
      "ready-file",
      long="ready-file",
      about="Write launch connection details as a private JSON file.",
    ),
    OptionArg(
      "viz-shell",
      long="viz-shell",
      about="Session visualizer HTML shell used by Export and Share.",
    ),
    OptionArg(
      "viz-bundle",
      long="viz-bundle",
      about="Session visualizer JS bundle used by Export and Share.",
    ),
  ],
)

///|
fn option(matches : @argparse.Matches, name : String) -> String? {
  if matches.values.get(name) is Some([value, ..]) {
    Some(value)
  } else {
    None
  }
}

///|
async fn main {
  let matches = command.parse(argv=@env.args()[1:], env=@env.get_env_vars())
  let port = @string.parse_int(option(matches, "port").unwrap_or("27184"))
  guard port >= 0 && port <= 65535 else {
    fail("port must be between 0 and 65535")
  }
  let runtime_dir = if option(matches, "runtime-dir") is Some(dir) {
    @fs.mkdir(dir, recursive=true, allow_exist=true)
    Some(@pathx.Path(dir))
  } else {
    @backend_host.prepared_runtime_dir(
      @env.args().get(0).unwrap_or("seekmoon-server"),
    )
  }
  // Keep the launcher readiness record separate from backend service logs.
  guard runtime_dir is Some(runtime_dir) else {
    fail("cannot determine the per-user runtime directory; pass --runtime-dir")
  }
  @xlog.global().set_handler(
    @xlog.File(runtime_dir.join("openseek-server.log").to_string()),
  )
  let engine = option(matches, "engine").unwrap_or("openseek")
  let engine = if engine.contains("/") || engine.contains("\\") {
    @pathx.Path(engine).resolve().to_string()
  } else {
    engine
  }
  let server = @host.Server::bind(engine~, port~, runtime_dir~, resources={
    ..@backend_host.HostResources::from_path(),
    viz: match (option(matches, "viz-shell"), option(matches, "viz-bundle")) {
      (Some(shell), Some(bundle)) => Some({ shell, bundle, })
      (None, None) => None
      _ => fail("--viz-shell and --viz-bundle must be supplied together")
    },
  })
  let ready : Json = {
    "url": server.url(),
    "token": server.token(),
    "entry_url": server.entry_url(),
  }
  server.run(
    root?=option(matches, "root"),
    entry=option(matches, "entry").unwrap_or("index.html"),
    on_ready=() => {
      if option(matches, "ready-file") is Some(path) {
        let temporary = path + "." + @uuid.mint() + ".tmp"
        defer (@fs.remove(temporary) catch { _ => () })
        @fs.write_file(
          temporary,
          ready.stringify(),
          create_mode=CreateNew,
          permission=0o600,
        )
        secure_ready_file(temporary)
        @fs.rename(temporary, path, replace=true)
      }
      println(ready.stringify())
    },
  )
}

///|
#cfg(not(platform="windows"))
async fn secure_ready_file(path : String) -> Unit {
  @fs.chmod(path, 0o600)
}

///|
#cfg(platform="windows")
async fn secure_ready_file(path : String) -> Unit noraise {
  ignore(path)
}
