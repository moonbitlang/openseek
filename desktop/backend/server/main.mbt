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
  @remote.serve_app_server(state, @stdio.stdin, @stdio.stdout)
}
