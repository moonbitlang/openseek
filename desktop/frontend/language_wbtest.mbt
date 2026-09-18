///|
test "language restore and selection project the effective locale into child inputs" {
  let dispatch = @cmd.Emit(_ => @cmd.none)
  let (_, restored) = update(
    dispatch,
    LanguageLoaded(Some(SimplifiedChinese), ["en"]),
    test_model(),
  )
  assert_eq(restored.language, @i18n.Preference::SimplifiedChinese)
  assert_eq(restored.locale, @i18n.Locale::SimplifiedChinese)
  assert_eq(restored.sidebar_component_input().locale, restored.locale)
  let (_, selected) = update(dispatch, LanguageChanged("en", ["zh-CN"]), {
    ..restored,
    select_menu: Some(LanguageMenu),
  })
  assert_eq(selected.locale, @i18n.Locale::English)
  assert_true(selected.select_menu is None)
  let (_, invalid) = update(
    dispatch,
    LanguageChanged("invalid", ["zh-CN"]),
    selected,
  )
  assert_eq(invalid.language, selected.language)
  assert_eq(invalid.locale, selected.locale)
}

///|
test "system language changes preserve explicit choices and unrelated application state" {
  let dispatch = @cmd.Emit(_ => @cmd.none)
  let initial = test_model()
  let (_, system) = update(dispatch, LanguageLoaded(None, ["zh-CN"]), initial)
  assert_eq(system.language, @i18n.Preference::System)
  assert_eq(system.locale, @i18n.Locale::SimplifiedChinese)
  let (_, changed) = update(dispatch, SystemLanguagesChanged(["en-US"]), system)
  assert_eq(changed.locale, @i18n.Locale::English)
  assert_true(changed.quick_open == initial.quick_open)
  assert_eq(changed.active_session, initial.active_session)
  let (_, fixed) = update(dispatch, LanguageChanged("zh-Hans", ["en"]), changed)
  let (_, unchanged) = update(dispatch, SystemLanguagesChanged(["en"]), fixed)
  assert_eq(unchanged.locale, @i18n.Locale::SimplifiedChinese)
  let (_, failed) = update(dispatch, LanguageStorageFailed("denied"), unchanged)
  assert_eq(failed.language, @i18n.Preference::SimplifiedChinese)
  assert_eq(failed.locale, @i18n.Locale::SimplifiedChinese)
  assert_eq(failed.notifications.length(), unchanged.notifications.length() + 1)
}
