///|
test "kind names are the registered presets and nothing else" {
  for name in ["explore", "review", "worker", "pattern-repair", "echo"] {
    assert_true(Kind::parse(name) is Some(_))
  }
  // No fallback: an unknown name, including the general agent's, is not a kind.
  assert_true(Kind::parse("general") is None)
  assert_true(Kind::parse("Explore") is None)
}
