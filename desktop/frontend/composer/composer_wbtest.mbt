// Whitebox tests for the package-private completion grammar (`Trigger` and
// `Menu`) and for the CI-summary test that shared their blackbox file. A
// blackbox `_test.mbt` file cannot reach the grammar, so it lives here.

///|
test "trigger grammar honors the caller's marker set" {
  guard Trigger::parse("Inspect #parse", inline_markers="#@") is Some(symbol) else {
    fail("symbol trigger expected")
  }
  inspect(symbol.marker(), content="#")
  inspect(symbol.query(), content="parse")
  inspect(symbol.draft_without_token(), content="Inspect ")
  assert_true(symbol.matches(["parse_hover"]))
  assert_false(symbol.matches(["render"]))
  assert_true(Trigger::parse("Use $review", inline_markers="#@") is None)
  assert_true(Trigger::parse("Use $review", inline_markers="$#") is Some(_))
}

///|
test "trigger grammar rejects embedded and completed tokens" {
  assert_true(Trigger::parse("price#parse", inline_markers="#") is None)
  assert_true(Trigger::parse("Inspect #parse now", inline_markers="#") is None)
  guard Trigger::parse("/comp", inline_markers="") is Some(command) else {
    fail("slash command trigger expected")
  }
  inspect(command.marker(), content="/")
  inspect(command.query(), content="comp")
}

///|
test "menu wraps selection and exposes the selected row" {
  let menu = Menu(["a", "b", "c"], loading=false, draft_without_token="")
  inspect(menu.selected(), content="0")
  inspect(menu.shifted(-1).selected(), content="2")
  guard menu.shifted(1).current() is Some(current) else { fail("row expected") }
  inspect(current, content="b")
  inspect(menu.shifted(1).shifted(1).shifted(1).selected(), content="0")
}

///|
test "Spanish check summaries preserve counts and plural agreement" {
  let single = GitChecks(passed=1, failed=1, pending=0)
  assert_eq(single.summary(locale=@i18n.Spanish), "1 fallida · 1 superada")
  let multiple = GitChecks(passed=3, failed=2, pending=4)
  assert_eq(
    multiple.summary(locale=@i18n.Spanish),
    "2 fallidas · 4 en ejecución · 3 superadas",
  )
}
