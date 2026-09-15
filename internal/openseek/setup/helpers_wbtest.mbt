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

///|
/// Test helper: split a composed system prompt at the environment block it
/// ends with, so the assertions below can target that block — or the
/// cache-shared prefix before it — without re-implementing its text. Callers
/// pin `OPENSEEK_GLOBAL_SKILLS_DIR` off, so nothing follows the block.
fn split_composed_prompt(prompt : String) -> (String, String) raise {
  // `split_once` yields the text after the heading, so the heading is put
  // back: the returned block still starts where the snapshots expect it to.
  let heading = "## Environment"
  guard prompt.split_once(heading) is Some((prefix, body)) else {
    fail("composed prompt carries no environment block:\n\{prompt}")
  }
  (prefix.to_owned(), "\{heading}\{body}")
}
