///|
test "UI language codec distinguishes missing from malformed" {
  let absent : @protocol.UiLanguagePreference = @json.from_json({})
  assert_eq(absent.language, None)
  let null_value : @protocol.UiLanguagePreference = @json.from_json({
    "language": null,
  })
  assert_eq(null_value.language, None)
  let chinese : @protocol.UiLanguagePreference = @json.from_json({
    "language": "zh-Hans",
    "future": true,
  })
  assert_eq(chinese.language, Some("zh-Hans"))
  assert_eq(chinese.to_json(), { "language": "zh-Hans" })
  let malformed = try {
    let _ : @protocol.UiLanguagePreference = @json.from_json({ "language": 42 })
    false
  } catch {
    _ => true
  }
  assert_true(malformed)
}
