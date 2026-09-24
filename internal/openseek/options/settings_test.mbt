///|
test "cli parses env backed options and task" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_MODEL": "deepseek-v4-pro",
    "OPENSEEK_API_URL": "https://proxy.example/v1/chat/completions",
    "OPENSEEK_MAX_STEPS": "120",
    "OPENSEEK_SYSTEM_PROMPT_FILE": "/tmp/prompt-a.md",
    "OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE": "/tmp/prompt-b.md",
    "OPENSEEK_RETRY_ATTEMPTS": "4",
    "OPENSEEK_RETRY_BACKOFF_MS": "25",
  })
  let (model, _, api_url) = @options.agent_settings(parsed)
  assert_true(model is Deepseek(V4Pro))
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  guard api_url is Some(url) else { fail("expected api url") }
  assert_eq(url, "https://proxy.example/v1/chat/completions")
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(@options.max_steps(parsed) is Some(120))
  assert_eq(@cli.value(parsed, "system-prompt-file"), "/tmp/prompt-a.md")
  assert_eq(
    @cli.value(parsed, "system-prompt-addendum-file"),
    "/tmp/prompt-b.md",
  )
  assert_false(parsed is { values: { "session": [_, ..], .. }, .. })
  assert_eq(@options.task_text(parsed), "write MoonBit")
  assert_eq(@options.retry_overrides(parsed), (Some(4), Some(25)))
}

///|
test "cli defaults model and max steps" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let (model, thinking, api_url) = @options.agent_settings(parsed)
  assert_true(model is Deepseek(V4Flash))
  assert_true(thinking is High)
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  assert_true(api_url is None)
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(@options.max_steps(parsed) is None)
  assert_true(parsed is { values: { "session"? : None, .. }, .. })
  // Absent on both halves: the DeepSeek client keeps its own defaults, which
  // the CLI never restates.
  assert_eq(@options.retry_overrides(parsed), (None, None))
}

///|
test "deepseek_api_key is the trimmed dedicated credential, or absent" {
  let keyed = @testkit.run_matches(argv=["task"], env={ "DEEPSEEK": " dk " })
  assert_eq(@options.deepseek_api_key(keyed), Some("dk"))
  let blank = @testkit.run_matches(argv=["task"], env={ "DEEPSEEK": "  " })
  assert_true(@options.deepseek_api_key(blank) is None)
  let keyless = @testkit.run_matches(argv=["task"], env=Map([]))
  assert_true(@options.deepseek_api_key(keyless) is None)
}
