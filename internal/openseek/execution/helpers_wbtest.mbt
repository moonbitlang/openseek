///|
/// Test helper: block until the asker has registered its pending entry. It
/// registers before it blocks, so wait for that rather than assuming the
/// spawn already ran.
async fn await_standing(desk : ApprovalDesk) -> Unit {
  for _ in 0..<200 {
    if desk.standing() is Some(_) {
      break
    }
    @async.sleep(5)
  }
}

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
