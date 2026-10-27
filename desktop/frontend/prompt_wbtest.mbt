///|
test "prompt default is copied into new chats without changing existing drafts" {
  let original = {
    ..test_conversation(),
    task: "keep this draft",
    composer_draft_present: true,
  }
  let model = test_model().replace_conversation(original)
  let custom = "  Custom instructions\n中文\n"
  let (_, changed) = update(
    test_dispatch(),
    Prompt(@prompt.Edited(custom)),
    model,
  )
  let complete_prompt = changed.default_prompt.text(changed.default_model)
  assert_true(complete_prompt != custom)
  assert_eq(changed.active().system_prompt, original.system_prompt)
  let fresh = changed.activate(
    Local,
    "fresh-prompt",
    @interop.ChannelId::Local.test_project(),
  )
  assert_eq(fresh.active().system_prompt, complete_prompt)
  let (_, changed_again) = update(
    test_dispatch(),
    Prompt(@prompt.Selected("builtin_moonbit_guide")),
    fresh,
  )
  assert_eq(changed_again.active().system_prompt, complete_prompt)
  let returned = changed_again.activate(
    Local,
    original.session_id,
    original.project(),
  )
  assert_eq(returned.active().system_prompt, original.system_prompt)
}

///|
test "loaded empty custom prompt seeds future chats without changing existing ones" {
  let older = test_model()
  let (_, saved) = @prompt.Model::new().update(Edited(""))
  let (_, loaded) = update(
    test_dispatch(),
    Prompt(@prompt.Loaded(saved)),
    older,
  )
  assert_eq(loaded.active().system_prompt, older.active().system_prompt)
  assert_eq(
    loaded.default_prompt.text(loaded.default_model),
    saved.text(loaded.default_model),
  )
  assert_false(saved.text(loaded.default_model).is_empty())
  let fresh = loaded.activate(
    Local,
    "loaded-prompt",
    @interop.ChannelId::Local.test_project(),
  )
  assert_eq(
    fresh.active().system_prompt,
    saved.text(fresh.active().engine_model),
  )
}

///|
test "session snapshots do not replace the draft prompt" {
  let conversation = {
    ..test_conversation(),
    system_prompt: "Custom instructions",
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
  assert_eq(refreshed.active().system_prompt, conversation.system_prompt)
}
