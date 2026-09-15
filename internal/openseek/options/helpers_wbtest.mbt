///|
/// Test helper: the raising parse as a `Result`, so a test can state both what
/// a value parses to and what a refusal says.
fn try_approval_policy(
  value : String,
  interactive~ : Bool,
) -> Result[ApprovalPolicy, String] {
  Ok(parse_approval_policy(value, interactive~)) catch {
    error => Err("\{error}")
  }
}

///|
/// Test helper: parse `run <argv>` and return the `run` subcommand's `Matches`
/// (what `run_task_command` and the accessors see). Mirrors real invocation.
fn run_matches(
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard root_command().parse(argv=["run", ..argv], env~).subcommand
    is Some((_, sm)) else {
    fail("expected a run subcommand")
  }
  sm
}

///|
/// Test helper: parse `sessions <sub> <argv>` and return the leaf subcommand's
/// `Matches` (what `sessions_list`/`sessions_show`/`sessions_compact` see).
fn sessions_leaf_matches(
  sub~ : String,
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard root_command().parse(argv=["sessions", sub, ..argv], env~).subcommand
    is Some((_, ssm)) else {
    fail("expected a sessions subcommand")
  }
  guard ssm.subcommand is Some((_, leaf)) else {
    fail("expected a sessions leaf subcommand")
  }
  leaf
}
