///|
/// `--no-session` combined with an explicit `--session` is a contradiction
/// every mode rejects up front, before any workspace or session work.
pub fn reject_session_contradiction(matches : @argparse.Matches) -> Unit raise {
  if matches
    is {
      flags: { "no-session": true, .. },
      values: { "session": [session, ..], .. },
      ..
    } &&
    !session.is_blank() {
    fail("--no-session contradicts --session; pick one behavior")
  }
}
