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
  assert_true(changed.active().moonbit_guide)
  let fresh = changed.activate(
    Local,
    "fresh-guide",
    @interop.ChannelId::Local.test_project(),
  )
  assert_false(fresh.active().moonbit_guide)
  let (_, changed_again) = update(
    test_dispatch(),
    MoonBitGuideDefaultChanged(true),
    fresh,
  )
  assert_false(changed_again.active().moonbit_guide)
  let returned = changed_again.activate(
    Local,
    original.session_id,
    original.project(),
  )
  assert_true(returned.active().moonbit_guide)
}

///|
test "loaded MoonBit preference seeds future chats without changing existing ones" {
  let older = test_model()
  let (_, loaded) = update(
    test_dispatch(),
    MoonBitGuideDefaultLoaded(false),
    older,
  )
  assert_true(loaded.active().moonbit_guide)
  assert_false(loaded.default_moonbit_guide)
  let fresh = loaded.activate(
    Local,
    "loaded-guide",
    @interop.ChannelId::Local.test_project(),
  )
  assert_false(fresh.active().moonbit_guide)
}

///|
test "session snapshots do not replace the draft creation choice" {
  let conversation = {
    ..test_conversation(),
    moonbit_guide: false,
    sync: test_reloading([]),
  }
  let model = test_model().replace_conversation(conversation)
  let (_, refreshed) = update_dev(
    test_dispatch(),
    SessionRefreshed(
      session=conversation.session_id,
      items=[],
      watermark=0,
      goal=None,
      goal_markers=[],
      prediction=None,
      generation=1,
    ),
    model,
  )
  assert_false(refreshed.active().moonbit_guide)
}
