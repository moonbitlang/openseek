///|
test "independent language sources, live binding, and widget disposal" {
  let first = @localization.Localization()
  let second = @localization.Localization(language=SimplifiedChinese)
  let seen = []
  let binding = first.bind(language => seen.push(language))
  assert_eq(seen.length(), 1)
  first.set_language(SimplifiedChinese)
  assert_eq(seen.length(), 2)
  first.set_language(SimplifiedChinese)
  assert_eq(seen.length(), 2)
  second.set_language(English)
  assert_eq(first.language(), SimplifiedChinese)
  binding.dispose()
  first.set_language(English)
  assert_eq(seen.length(), 2)
  first.dispose()
  second.dispose()
}

///|
test "traditional Chinese updates a shared source and localized labels" {
  let source = @localization.Localization()
  let seen = []
  let binding = source.bind(language => seen.push(language))
  source.set_language(TraditionalChinese)
  assert_eq(seen, [English, TraditionalChinese])
  assert_eq(source.text(CopyLabel), "複製")
  source.set_language(TraditionalChinese)
  assert_eq(seen.length(), 2)
  binding.dispose()
  source.dispose()
}
