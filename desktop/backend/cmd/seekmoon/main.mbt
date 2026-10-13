///|
/// The `seekmoon` command an agent runs to use its host's tools. Everything
/// it does is `@mcp.cli`; this only connects that to the process.
async fn main {
  let outcome = @mcp.cli(@env.args()[1:].to_owned(), @env.get_env_vars())
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
