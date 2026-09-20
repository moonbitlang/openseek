///|
/// A phone's titlebar carries no detail toggle, so the narrow layout must
/// always render the minimal transcript even when the stored preference asks
/// for the detailed view. The preference itself is preserved for the wide
/// layout, which is why the effective value is derived rather than rewritten.
test "the narrow layout renders minimal regardless of the stored preference" {
  let model = test_model()
  let detailed = { ..model, narrow: false, minimal_transcript: false, }
  assert_false(detailed.minimal_transcript_effective())
  assert_true({ ..detailed, narrow: true, }.minimal_transcript_effective())
  let minimal = { ..detailed, minimal_transcript: true, }
  assert_true(minimal.minimal_transcript_effective())
  assert_true({ ..minimal, narrow: true, }.minimal_transcript_effective())
}
