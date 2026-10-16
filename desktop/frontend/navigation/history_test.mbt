///|
test "back forward branching and duplicate visits are pure" {
  let a : @routes.Location = { device: "d", target: Session("a"), }
  let b : @routes.Location = { device: "d", target: Settings, }
  let c : @routes.Location = { device: "d", target: Skills, }
  let h = @navigation.History::empty()
    .visit(a, replace=false)
    .visit(b, replace=false)
  let back = h.back()
  assert_true(back.current() == Some(a))
  assert_true(back.can_forward())
  assert_true(back.forward() == h)
  assert_true(h.visit(b, replace=false) == h)
  let fork = back.visit(c, replace=false)
  assert_true(!fork.can_forward())
  assert_true(fork.back().current() == Some(a))
  assert_true(h.current() == Some(b))
  assert_true(h.back() == back)
}

///|
test "draft promotion preserves history position" {
  let draft : @routes.Location = { device: "d", target: CodexDraft("draft"), }
  let thread : @routes.Location = { device: "d", target: Thread("thread"), }
  let settings : @routes.Location = { device: "d", target: Settings, }
  let h = @navigation.History::empty()
    .visit(draft, replace=false)
    .visit(settings, replace=false)
  let promoted = h.promote(draft, thread)
  assert_true(promoted.current() == Some(settings))
  assert_true(promoted.back().current() == Some(thread))
  assert_true(!promoted.back().can_back())
}
