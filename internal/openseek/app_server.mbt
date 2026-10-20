///|
/// The native companion ships alongside the portable CLI. Application RPC
/// stays on TCP; inherited stdio is only endpoint discovery and owner lifetime.
async fn run_app_server() -> Unit {
  let suffix = if @env.args()[0].has_suffix(".exe") { ".exe" } else { "" }
  let sibling = @path.Path(@env.args()[0])
    .dirname()
    .join(Path("openseek-app-server" + suffix))
    .to_string()
  let server = match @env.get_env_var("OPENSEEK_APP_SERVER") {
    Some(path) => path
    None =>
      if ((@fs.kind(sibling) is Regular) catch { _ => false }) {
        sibling
      } else {
        "openseek-app-server"
      }
  }
  let code = @process.run(
    server,
    [],
    extra_env=Map([
      (
        "OPENSEEK_ENGINE",
        @env.get_env_var("OPENSEEK_ENGINE").unwrap_or(@env.args()[0]),
      ),
    ]),
    stdin=@stdio.stdin,
    stdout=@stdio.stdout,
    stderr=@stdio.stderr,
    cancel_handler=@process.graceful_cancel(timeout=1000),
  )
  guard code == 0 else { fail("app-server exited \{code}") }
}
