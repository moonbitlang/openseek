///|
test "switching prompt sources preserves custom text" {
  let model : @deepseek.Model = Deepseek(V4Flash)
  let custom = "  Project instructions\n中文与 `code`\n"
  let (_, edited) = Model::new().update(Edited(custom))
  let (_, builtin) = edited.update(Selected("builtin_moonbit_guide"))
  assert_eq(builtin.text(model), Model::new().text(model))
  let (_, restored) = builtin.update(Selected("custom"))
  assert_eq(restored.text(model), edited.text(model))
  let (_, cleared) = restored.update(Edited(""))
  let (_, builtin) = cleared.update(Selected("builtin_moonbit_guide"))
  let (_, restored) = builtin.update(Selected("custom"))
  assert_eq(restored.text(model), cleared.text(model))
}

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
