///|
async fn main {
  let executable = @executable.current_exe()
  let suffix = if executable.has_suffix(".exe") { ".exe" } else { "" }
  let engine = @env.get_env_var("OPENSEEK_ENGINE").unwrap_or(
    @path.Path(executable).dirname().join(Path("openseek" + suffix)).to_string(),
  )
  let runtime_dir = @host.prepared_runtime_dir(executable)
  let host_mcp = @mcp.Server([], version="ssh-1")
  let state = @api.ApiState(engine~, runtime_dir?, host_mcp~)
  // Opt-in browser console for tests: `OPENSEEK_APP_SERVER_CONSOLE` names a
  // built `dist/browser` directory, which this process then serves on an
  // ephemeral loopback port with the same `@remote.LocalConsole` a
  // development window uses. Stdout already carries the service
  // announcement, so the console origin goes to stderr as one JSON line.
  // Unset, the process opens no port beyond the app-server's own.
  guard @env.get_env_var("OPENSEEK_APP_SERVER_CONSOLE") is Some(root) else {
    @remote.serve_app_server(state, @stdio.stdin, @stdio.stdout)
    return
  }
  let console = @remote.LocalConsole::bind(port=0)
  @stdio.stderr.write(
    ({ "console": console.origin() } : Json).stringify() + "\n",
  )
  @async.with_task_group(group => {
    // The console lives exactly as long as the app-server: it ends when the
    // owning connection closes, and that ends this group.
    group.spawn_bg(no_wait=true, () => {
      console.run(state, root~, entry="index.html")
    })
    @remote.serve_app_server(state, @stdio.stdin, @stdio.stdout)
  })
}
