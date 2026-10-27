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
