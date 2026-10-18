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

///|
test "a review takes exactly one of a goal or a base" {
  assert_true(
    ReviewTarget::parse({ "goal": "tests pass" })
    is Ok(Goal(goal="tests pass", baseline=None)),
  )
  assert_true(
    ReviewTarget::parse({ "goal": "tests pass", "sha": "abc", "dirty": true })
    is Ok(Goal(baseline=Some({ sha: "abc", dirty: true, }), ..)),
  )
  assert_true(
    ReviewTarget::parse({ "base": "origin/main" }) is Ok(Base("origin/main")),
  )
  assert_eq(
    Kind::Review.check_input({ "goal": "tests pass", "base": "origin/main" }),
    Some("review takes a goal or a base, not both"),
  )
  let refused : Array[Json] = [
    {},
    { "goal": " " },
    { "base": "" },
    { "base": 1 },
  ]
  for input in refused {
    assert_eq(
      Kind::Review.check_input(input),
      Some("review requires a non-empty goal or base"),
    )
  }
}

///|
test "only a scout takes instructions from its launcher" {
  assert_true(Kind::Explore.takes_instructions())
  // A reviewer has no ingress: the agent it audits would be the one posting.
  for kind in [Kind::Review, Worker, PatternRepair, Echo] {
    assert_false(kind.takes_instructions())
  }
}

///|
test "an instruction is framed as the launcher's and tagged with its receipt" {
  assert_eq(launcher_of("desktop-7-sr-3"), Some("desktop-7"))
  // The innermost suffix names the launcher; a top-level run has none.
  assert_eq(launcher_of("desktop-7-sr-3-sr-1"), Some("desktop-7-sr-3"))
  assert_eq(launcher_of("desktop-7"), None)
  let message : @inbox.Message = {
    id: "m1",
    from: "desktop-7",
    text: "Only production callers.",
  }
  guard launcher_instruction(message)
    is Prompt(Content([Text(text)]), submission_id=Some(tag)) else {
    fail("an instruction is a tagged prompt")
  }
  assert_eq(tag, message.receipt())
  assert_eq(tag, "m1@desktop-7")
  assert_true(text.has_prefix("[New instruction from the agent that gave you"))
  assert_true(text.has_suffix("\nOnly production callers."))
}

///|
/// A blank body must not reach the turn: framed, it has content, and content
/// arriving while a scout submits discards its report.
test "only the launcher's messages with something to say are presented" {
  let messages : Array[@inbox.Message] = [
    { id: "m1", from: "p", text: "Skip the tests.", },
    { id: "m2", from: "p", text: "  \n ", },
    { id: "m3", from: "q", text: "From another conversation.", },
    { id: "m4", from: "p-sr-2", text: "From a sibling.", },
  ]
  guard launcher_instructions(messages, Some("p"))
    is [Prompt(_, submission_id=Some("m1@p"))] else {
    fail("exactly the launcher's one non-blank message is presented")
  }
  // A run that is nobody's child presents nothing at all.
  assert_true(launcher_instructions(messages, None) is [])
}
