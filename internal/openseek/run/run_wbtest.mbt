///|
test "a kind's step ceiling: explicit flag, then request, then environment, then default" {
  let env = { "OPENSEEK_MAX_STEPS": "30" }
  let flag = @testkit.run_matches(argv=["--max-steps", "10", "task"], env~)
  assert_eq(step_ceiling(flag, Some(20), 100), 10)
  let env_only = @testkit.run_matches(argv=["task"], env~)
  // The request is about this call; the environment is a standing default.
  assert_eq(step_ceiling(env_only, Some(20), 100), 20)
  assert_eq(step_ceiling(env_only, None, 100), 30)
  let bare = @testkit.run_matches(argv=["task"], env={})
  assert_eq(step_ceiling(bare, None, 100), 100)
}

///|
test "kind names are the registered presets and nothing else" {
  for name in ["explore", "review", "worker", "pattern-repair", "echo"] {
    assert_true(Kind::parse(name) is Some(_))
  }
  // No fallback: an unknown name, including the general agent's, is not a kind.
  assert_true(Kind::parse("general") is None)
  assert_true(Kind::parse("Explore") is None)
}
