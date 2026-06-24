///|
fn installed_skill(
  name : String,
  description : String,
) -> @transcript.InstalledSkillItem {
  { id: name, name, description, source: "" }
}

///|
test "slash trigger lists matching commands and filters by the typed name" {
  guard compute_completion("/", []) is Some(all) else {
    fail("a bare slash should open the command menu")
  }
  assert_true(all.kind is SlashCommands)
  assert_true(all.items.length() >= 1)
  assert_eq(all.items[0].label, "/compact")
  guard compute_completion("/comp", []) is Some(match_) else {
    fail("a command prefix should keep matching rows")
  }
  assert_eq(match_.items[0].command, "compact")
  // No command contains this, so the menu closes rather than showing nothing.
  assert_true(compute_completion("/zzz", []) is None)
}

///|
test "a completed command word closes the menu" {
  // The space marks the command as typed; further text is its argument.
  assert_true(compute_completion("/compact now", []) is None)
}

///|
test "dollar trigger lists installed skills, name or description matching" {
  let skills = [
    installed_skill("review-pr", "Review a pull request"),
    installed_skill("refactor", "Tidy code"),
  ]
  guard compute_completion("$", skills) is Some(all) else {
    fail("a bare dollar should open the skills menu")
  }
  assert_true(all.kind is SkillMentions)
  assert_eq(all.items.length(), 2)
  assert_eq(all.items[0].label, "$review-pr")
  // Insertion drops the bare name plus a space to keep typing the prompt.
  assert_eq(all.items[0].insert, "review-pr ")
  // Matches the description too, case-insensitively.
  guard compute_completion("$TIDY", skills) is Some(desc) else {
    fail("description text should match")
  }
  assert_eq(desc.items[0].label, "$refactor")
  // No installed skills, no menu.
  assert_true(compute_completion("$x", []) is None)
}

///|
test "plain text opens no completion menu" {
  assert_true(compute_completion("hello world", []) is None)
  assert_true(compute_completion("", []) is None)
}

///|
test "highlight movement wraps at both ends" {
  let skills = [
    installed_skill("a", ""),
    installed_skill("b", ""),
    installed_skill("c", ""),
  ]
  guard compute_completion("$", skills) is Some(menu) else {
    fail("menu expected")
  }
  assert_eq(menu.selected, 0)
  assert_eq(menu.shifted(-1).selected, 2)
  assert_eq(menu.shifted(1).selected, 1)
  assert_eq(menu.shifted(1).shifted(1).shifted(1).selected, 0)
}
