///|
test "host snapshots update committed prompts without discarding unsaved text" {
  let model = Model::new().receive("custom", "saved")
  let (_, edited) = model.update(Edited("  unsaved\n中文\n"))
  assert_eq(edited.text(Deepseek(V4Flash)), model.text(Deepseek(V4Flash)))
  let remote = edited.receive("builtin_moonbit_guide", "another client")
  assert_eq(remote.draft_text(), Some("  unsaved\n中文\n"))
  let saved = remote.receive("custom", "  unsaved\n中文\n")
  assert_true(saved.draft_text() is None)
  assert_true(saved.text(Deepseek(V4Flash)).has_suffix("  unsaved\n中文\n"))
  let (_, cleared) = saved.update(Edited(""))
  assert_eq(cleared.draft_text(), Some(""))
  assert_true(cleared.receive("custom", "").draft_text() is None)
}
