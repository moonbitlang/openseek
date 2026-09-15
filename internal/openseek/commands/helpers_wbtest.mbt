///|
/// Test helper: parse `sessions <sub> <argv>` and return the leaf subcommand's
/// `Matches` (what `sessions_list`/`sessions_show`/`sessions_compact` see).
fn sessions_leaf_matches(
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
