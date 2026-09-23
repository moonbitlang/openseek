///|
test "draft prompt encoding belongs to composer" {
  let draft : @composer.Draft = {
    images: [],
    task: "inspect this",
    mentions: [
      { ref_: @mention_context.File(path="src/main.mbt"), range: None, },
    ],
  }
  assert_true(draft.prompt().contains("<user_mentions>"))
  assert_true(draft.prompt().contains("inspect this"))
}
