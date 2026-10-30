///|
test "selecting a new component state replaces only that revision's chip" {
  let first : @mention_context.ArtifactSnapshot = {
    reference: "artifact://answer-v1.html",
    title: "First",
    state: { "value": 1 },
  }
  let second = { ..first, title: "Second", state: { "value": 2 }, }
  let other = { ..first, reference: "artifact://other.html", }
  let draft : @composer.Draft = {
    task: "Keep my question",
    images: [],
    mentions: [{ ref_: @mention_context.File(path="notes.md"), range: None, }],
  }
  let selected = draft
    .with_artifact_snapshot(first)
    .with_artifact_snapshot(other)
    .with_artifact_snapshot(second)
  assert_eq(selected.task, draft.task)
  assert_eq(selected.mentions.length(), 3)
  assert_eq(selected.mentions[0], draft.mentions[0])
  assert_true(
    selected.mentions[2].ref_ is @mention_context.InteractiveAnswer(value) &&
    value == second,
  )
  guard selected.user_item() is User(content~) else {
    fail("expected a user message")
  }
  assert_true(@composer.Draft::from_content(content) == Some(selected))
}
