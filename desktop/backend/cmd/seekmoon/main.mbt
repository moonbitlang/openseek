///|
/// The `seekmoon` command, through which an agent uses its host's tools.
/// Everything it does is in `@mcp`; this only connects that to the process.
async fn main {
  let outcome : @mcp.CliOutcome = match @env.args()[1:] {
    [@mcp.McpCommand, .. args] =>
      @mcp.serve_stdio(
        args.to_owned(),
        @env.get_env_vars(),
        @stdio.stdin,
        @stdio.stdout,
      )
    _ => { code: 2, stdout: "", stderr: "usage: seekmoon mcp [GROUP]...", }
  }
  if !outcome.stdout.is_empty() {
    @stdio.stdout.write(outcome.stdout + "\n")
  }
  if !outcome.stderr.is_empty() {
    @stdio.stderr.write(outcome.stderr + "\n")
  }
  if outcome.code != 0 {
    @sys.exit(outcome.code)
  }
}
