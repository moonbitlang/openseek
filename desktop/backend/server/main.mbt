///|
async fn main {
  let engine = @env.get_env_var("OPENSEEK_ENGINE").unwrap_or("openseek")
  let runtime_dir = @host.prepared_runtime_dir(@env.args()[0])
  let host_mcp = @mcp.Server([], version="ssh-1")
  let state = @api.ApiState(engine~, runtime_dir?, host_mcp~)
  @remote.serve_app_server(state, @stdio.stdin, @stdio.stdout)
}
