///|
test "language preference round trips and invalid values stay absent" {
  for
    preference in [
      @i18n.System,
      @i18n.English,
      @i18n.SimplifiedChinese,
      @i18n.Japanese,
    ] {
    assert_eq(@i18n.Preference::parse(preference.wire()), Some(preference))
  }
  assert_eq(@i18n.Preference::parse(""), None)
  assert_eq(@i18n.Preference::parse("中文"), None)
  assert_eq(@i18n.Preference::parse("zh-Hant"), None)
}

///|
test "system follows ordered supported languages and explicit script" {
  let system = @i18n.Preference::System
  for tag in ["zh", "zh-CN", "zh-SG", "zh-Hans", "ZH-hANS-TW"] {
    assert_eq(system.resolve([tag]), @i18n.Locale::SimplifiedChinese)
  }
  for tag in ["zh-TW", "zh-HK", "zh-MO", "zh-Hant-CN", "fr", ""] {
    assert_eq(system.resolve([tag]), @i18n.Locale::English)
  }
  assert_eq(system.resolve([]), @i18n.Locale::English)
  for tag in ["ja", "ja-JP", "JA-jp"] {
    assert_eq(system.resolve([tag]), @i18n.Locale::Japanese)
  }
  assert_eq(system.resolve(["fr", "ja-JP", "zh-CN"]), @i18n.Locale::Japanese)
  assert_eq(system.resolve(["en", "ja"]), @i18n.Locale::English)
  assert_eq(
    @i18n.Preference::Japanese.resolve(["zh-CN"]),
    @i18n.Locale::Japanese,
  )
  assert_eq(@i18n.Locale::Japanese.tag(), "ja")
  assert_eq(
    system.resolve(["fr", "zh-CN", "en"]),
    @i18n.Locale::SimplifiedChinese,
  )
  assert_eq(system.resolve(["en-US", "zh-CN"]), @i18n.Locale::English)
  assert_eq(@i18n.Preference::English.resolve(["zh-CN"]), @i18n.Locale::English)
  assert_eq(
    @i18n.Preference::SimplifiedChinese.resolve(["en"]),
    @i18n.Locale::SimplifiedChinese,
  )
}
