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

///|
test "sent message draft recovers text mentions and images without losing attachments" {
  let original : @composer.Draft = {
    task: "解释这个 🌓 image",
    mentions: [
      { ref_: @mention_context.File(path="src/main.mbt"), range: None, },
      { ref_: @mention_context.Skill(name="review-pr"), range: None, },
    ],
    images: [{ name: "Image", url: "data:image/png;base64,aW1hZ2U=", }],
  }
  guard original.user_item() is User(content~) else {
    fail("expected user content")
  }
  assert_true(@composer.Draft::from_content(content) == Some(original))
  assert_true(
    @composer.Draft::from_content(content) ==
    @composer.Draft::from_content(content),
  )
  assert_true(
    @composer.Draft::from_content(Content([File(file_id="provider-file")]))
    is None,
  )
  guard @composer.Draft::from_content(
      Content([ImageUrl(url="data:image/png;base64,aW1hZ2U=")]),
    )
    is Some(image_only) else {
    fail("image-only draft")
  }
  assert_eq(image_only.task, "")
  assert_eq(image_only.images.length(), 1)
}
