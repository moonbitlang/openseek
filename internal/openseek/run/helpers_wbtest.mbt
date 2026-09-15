///|
/// Test helper: parse `run <argv>` and return the `run` subcommand's `Matches`
/// (what `run_task_command` and the accessors see). Mirrors real invocation.
fn run_matches(
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard @options.root_command().parse(argv=["run", ..argv], env~).subcommand
    is Some((_, sm)) else {
    fail("expected a run subcommand")
  }
  sm
}
