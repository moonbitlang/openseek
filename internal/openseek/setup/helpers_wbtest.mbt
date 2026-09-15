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
