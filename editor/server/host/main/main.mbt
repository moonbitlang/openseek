///|
struct DevServerConfig {
  root : String
  host : String
  port : Int
  asset_dir : String
  moon_command : String
  /// Directory subtree the repository picker may browse and switch to.
  /// Empty means automatic: unrestricted on loopback binds, disabled on
  /// every other bind.
  browse_root : String
}

///|
async fn main {
  let config = parse_args(@env.args()[1:])
  @host.run_native_editor_server(
    config.root,
    host=config.host,
    port=config.port,
    asset_dir=config.asset_dir,
    moon_command=config.moon_command,
    browse_root=config.browse_root,
  ) catch {
    error => abort("Readonly editor native server failed: \{error.to_string()}")
  }
}

///|
fn parse_args(args : ArrayView[String]) -> DevServerConfig {
  let mut root = "."
  let mut host = "127.0.0.1"
  let mut port = 5173
  let mut asset_dir = "web/dist"
  let mut moon_command = "moon"
  let mut browse_root = ""
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--root" =>
        if i + 1 < args.length() {
          root = args[i + 1]
          i += 1
        }
      "--port" =>
        if i + 1 < args.length() {
          port = parse_port(args[i + 1], port)
          i += 1
        }
      "--host" =>
        if i + 1 < args.length() {
          host = args[i + 1]
          i += 1
        }
      "--asset-dir" =>
        if i + 1 < args.length() {
          asset_dir = args[i + 1]
          i += 1
        }
      "--moon-command" =>
        if i + 1 < args.length() {
          moon_command = args[i + 1]
          i += 1
        }
      "--browse-root" =>
        if i + 1 < args.length() {
          browse_root = args[i + 1]
          i += 1
        }
      _ => ()
    }
    i += 1
  }
  { root, host, port, asset_dir, moon_command, browse_root, }
}

///|
fn parse_port(value : String, fallback : Int) -> Int {
  @string.parse_int(value, base=10) catch {
    _ => fallback
  }
}
