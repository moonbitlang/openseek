///|
test "brief display rejects absent and blank text" {
  assert_eq(@brief_display.text(None), None)
  assert_eq(@brief_display.text(Some("")), None)
  assert_eq(@brief_display.text(Some(" \n\t ")), None)
}

///|
test "brief display trims padding without damaging Unicode" {
  assert_eq(
    @brief_display.text(Some("  🎉 读取 moon.mod  ")),
    Some("🎉 读取 moon.mod"),
  )
}

///|
test "call display owns the inline failure marker policy" {
  assert_eq(@brief_display.call_text(None, false), None)
  assert_eq(@brief_display.call_text(None, true), Some("🚩"))
  assert_eq(
    @brief_display.call_text(Some("  moon test  "), true),
    Some("moon test 🚩"),
  )
}
