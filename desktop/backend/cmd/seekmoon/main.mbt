///|
/// The `seekmoon` command an agent runs to use its host's tools. Everything
/// it does is in `@mcp`; this only connects that to the process.
async fn main {
  let env = @env.get_env_vars()
  let outcome = match @env.args()[1:] {
    // A server for as long as its client keeps stdin open, rather than one
    // tool run.
    [@mcp.McpCommand, .. args] =>
      @mcp.serve_stdio(args.to_owned(), env, @stdio.stdin, @stdio.stdout)
    args => @mcp.cli(args.to_owned(), env)
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
