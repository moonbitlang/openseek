///|
test "trigger grammar honors the caller's marker set" {
  guard @composer.Trigger::parse("Inspect #parse", inline_markers="#@")
    is Some(symbol) else {
    fail("symbol trigger expected")
  }
  inspect(symbol.marker(), content="#")
  inspect(symbol.query(), content="parse")
  inspect(symbol.draft_without_token(), content="Inspect ")
  assert_true(symbol.matches(["parse_hover"]))
  assert_false(symbol.matches(["render"]))
  assert_true(
    @composer.Trigger::parse("Use $review", inline_markers="#@") is None,
  )
  assert_true(
    @composer.Trigger::parse("Use $review", inline_markers="$#") is Some(_),
  )
}

///|
test "trigger grammar rejects embedded and completed tokens" {
  assert_true(
    @composer.Trigger::parse("price#parse", inline_markers="#") is None,
  )
  assert_true(
    @composer.Trigger::parse("Inspect #parse now", inline_markers="#") is None,
  )
  guard @composer.Trigger::parse("/comp", inline_markers="") is Some(command) else {
    fail("slash command trigger expected")
  }
  inspect(command.marker(), content="/")
  inspect(command.query(), content="comp")
}

///|
test "menu wraps selection and exposes the selected row" {
  let menu = @composer.Menu(
    ["a", "b", "c"],
    loading=false,
    draft_without_token="",
  )
  inspect(menu.selected(), content="0")
  inspect(menu.shifted(-1).selected(), content="2")
  guard menu.shifted(1).current() is Some(current) else { fail("row expected") }
  inspect(current, content="b")
  inspect(menu.shifted(1).shifted(1).shifted(1).selected(), content="0")
}
