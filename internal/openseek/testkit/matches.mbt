///|
/// Parse `run <argv>` and return the `run` subcommand's `Matches` — what the
/// command handlers and the option accessors see. Mirrors a real invocation,
/// so a test that goes through it exercises the real command tree.
///
/// Imported `for "wbtest"` only, so it adds no production API.
pub fn run_matches(
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard @options.root_command().parse(argv=["run", ..argv], env~).subcommand
    is Some((_, sm)) else {
    fail("expected a run subcommand")
  }
  sm
}

///|
/// Parse `sessions <sub> <argv>` and return the leaf subcommand's `Matches`
/// (what `sessions_list`/`sessions_show`/`sessions_compact` see).
pub fn sessions_leaf_matches(
  sub~ : String,
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard @options.root_command().parse(argv=["sessions", sub, ..argv], env~).subcommand
    is Some((_, ssm)) else {
    fail("expected a sessions subcommand")
  }
  guard ssm.subcommand is Some((_, leaf)) else {
    fail("expected a sessions leaf subcommand")
  }
  leaf
}
