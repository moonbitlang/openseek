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
