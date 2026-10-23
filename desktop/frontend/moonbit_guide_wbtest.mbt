///|
test "MoonBit guide default is copied into new chats without changing existing drafts" {
  let original = {
    ..test_conversation(),
    task: "keep this draft",
    composer_draft_present: true,
  }
  let model = test_model().replace_conversation(original)
  let (_, changed) = update(
    test_dispatch(),
    MoonBitGuideDefaultChanged(false),
    model,
  )
  assert_false(changed.default_moonbit_guide)
  assert_eq(changed.active().moonbit_guide, Some(true))
  let fresh = changed.activate(
    Local,
    "fresh-guide",
    @interop.ChannelId::Local.test_project(),
  )
  assert_eq(fresh.active().moonbit_guide, Some(false))
  let (_, changed_again) = update(
    test_dispatch(),
    MoonBitGuideDefaultChanged(true),
    fresh,
  )
  assert_eq(changed_again.active().moonbit_guide, Some(false))
  let returned = changed_again.activate(
    Local,
    original.session_id,
    original.project(),
  )
  assert_eq(returned.active().moonbit_guide, Some(true))
}

///|
test "loaded MoonBit preference seeds future chats and keeps older unknown state" {
  let older = test_model().replace_conversation({
    ..test_conversation(),
    moonbit_guide: None,
  })
  let (_, loaded) = update(
    test_dispatch(),
    MoonBitGuideDefaultLoaded(false),
    older,
  )
  assert_eq(loaded.active().moonbit_guide, None)
  assert_false(loaded.default_moonbit_guide)
  let fresh = loaded.activate(
    Local,
    "loaded-guide",
    @interop.ChannelId::Local.test_project(),
  )
  assert_eq(fresh.active().moonbit_guide, Some(false))
}
