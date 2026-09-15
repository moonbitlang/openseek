///|
/// Parse the whole `openseek` command tree and dispatch on the chosen subcommand.
/// The command tree requires a subcommand, so the parser rejects a bare
/// `openseek` (headless automation has no default action). argparse reads the
/// process arguments itself (dropping the program name); only the environment
/// has to be handed over, because `parse` defaults it to an empty map and the
/// `[env: OPENSEEK_*]` fallbacks would otherwise silently never fire.
pub async fn dispatch() -> Unit {
  let matches = @argparse.parse(
    @options.root_command(),
    env=@env.get_env_vars(),
  )
  // argparse rejects unknown and missing subcommands during parse, so the
  // absent case is unreachable.
  guard matches.subcommand is Some((name, m)) else {
    fail("missing subcommand (argparse should have rejected this)")
  }
  // Only the agent-running commands spawn children, and only they read the
  // setting at all: a malformed value must not break `sessions list`, for the
  // same reason `--api-key` is not argparse-`required`.
  if name is ("run" | "serve" | "review" | "subrun") {
    @options.export_retry_overrides(m)
  }
  match name {
    "run" => @run.run_task_command(m)
    "serve" => @serve.run_serve_command(m)
    "review" => @commands.run_review_command(m)
    "subrun" => @commands.run_subrun_command(m)
    "mcp" => @commands.run_mcp_command(m)
    "sessions" => @commands.run_sessions_command(m)
    name => fail("unhandled subcommand: \{name}")
  }
}
