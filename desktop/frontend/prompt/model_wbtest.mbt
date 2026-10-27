///|
test "stored prompt sources retain their independent editor contents" {
  for text in ["", "  Rules\n中文\n"] {
    let (_, custom) = Model::new().update(Edited(text))
    let (_, builtin) = custom.update(Selected("builtin_moonbit_guide"))
    for model in [custom, builtin] {
      let restored : Model = @json.from_json(ToJson::to_json(model))
      assert_true(restored == model)
      let (_, selected) = restored.update(Selected("custom"))
      assert_eq(selected.custom_text, text)
      assert_true(selected.source is Custom)
    }
  }
  let legacy_builtin : Model = @json.from_json({
    "kind": "builtin_moonbit_guide",
  })
  assert_true(legacy_builtin == Model::new())
  let legacy_custom : Model = @json.from_json({
    "kind": "custom",
    "text": "saved",
  })
  assert_eq(legacy_custom.custom_text, "saved")
  assert_true(legacy_custom.source is Custom)
}
