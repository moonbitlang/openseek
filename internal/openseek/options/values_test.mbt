///|
/// The DeepSeek flash tier's canonical wire name is `deepseek-flash`; the
/// retired `deepseek-v4-flash` name is accepted as an alias for the same tier.
test "cli accepts the canonical flash wire name" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_MODEL": "deepseek-flash",
  })
  let (model, thinking, api_url) = @options.agent_settings(parsed)
  assert_true(model is Deepseek(V4Flash))
  assert_eq(model.to_string(), "deepseek-flash")
  assert_eq(@cli.resolve_api_key(model, parsed), Some("test-key"))
  assert_true(thinking is High)
  assert_true(api_url is None)
}

///|
test "cli retry flags override the environment and reject non-positives" {
  let parsed = @testkit.run_matches(
    argv=["--retry-attempts", "2", "--retry-backoff-ms", "7", "write"],
    env={ "DEEPSEEK": "test-key", "OPENSEEK_RETRY_ATTEMPTS": "9" },
  )
  assert_eq(@options.retry_overrides(parsed), (Some(2), Some(7)))
  // Rejection is checked through the environment: argparse refuses a bare
  // `-1` as a missing value before the parsed string ever reaches here.
  for bad in ["0", "-1", "many"] {
    let rejected = @testkit.run_matches(argv=["write"], env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_RETRY_ATTEMPTS": bad,
    })
    try ignore(@options.retry_overrides(rejected)) catch {
      err =>
        assert_true(
          "\{err}".contains("--retry-attempts must be a positive integer"),
        )
    } noraise {
      _ => fail("expected --retry-attempts \{bad} to be rejected")
    }
  }
}

///|
/// The flag has to reach subagents, and they are handed the environment, not
/// this process's argv — see `export_retry_overrides`.
test "cli exports argv retry overrides into the environment for children" {
  let parsed = @testkit.run_matches(
    argv=["--retry-attempts", "3", "--retry-backoff-ms", "11", "write"],
    env={ "DEEPSEEK": "test-key" },
  )
  @options.export_retry_overrides(parsed)
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_ATTEMPTS"), Some("3"))
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_BACKOFF_MS"), Some("11"))
  @env.unset_env_var("OPENSEEK_RETRY_ATTEMPTS")
  @env.unset_env_var("OPENSEEK_RETRY_BACKOFF_MS")
  // Nothing to carry means nothing written: a child keeps falling back to the
  // client default rather than being pinned to a value nobody asked for.
  let bare = @testkit.run_matches(argv=["write"], env={ "DEEPSEEK": "test-key" })
  @options.export_retry_overrides(bare)
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_ATTEMPTS"), None)
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_BACKOFF_MS"), None)
}

///|
test "cli uses provider API keys only for their models" {
  let kimi = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "KIMI": "kimi-key",
    "OPENSEEK_MODEL": "kimi-k2.7-code-highspeed",
  })
  let kimi_model : @deepseek.Model = Kimi(K27CodeHighSpeed)
  assert_eq(@cli.resolve_api_key(kimi_model, kimi), Some("kimi-key"))
  let glm = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "GLM": "glm-key",
    "OPENSEEK_MODEL": "glm-5.3-flash",
  })
  let glm_model : @deepseek.Model = Glm(G53Flash)
  assert_eq(@cli.resolve_api_key(glm_model, glm), Some("glm-key"))
  let deepseek = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "KIMI": "kimi-key",
    "GLM": "glm-key",
  })
  // Provider keys are not fallbacks for a DeepSeek model: no arm matches, so
  // the caller sees `None` and reports it.
  let deepseek_model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(@cli.resolve_api_key(deepseek_model, deepseek) is None)
}

///|
test "agent runs require api key" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env=Map([]))
  let model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(@cli.resolve_api_key(model, parsed) is None)
}

///|
test "agent runs require task text" {
  let parsed = @testkit.run_matches(argv=[], env={ "DEEPSEEK": "test-key" })
  let _ = @options.task_text(parsed) catch {
    error => {
      assert_true("\{error}".contains("task description is required"))
      return
    }
  }
  fail("missing task accepted")
}

///|
test "cli parses max steps option" {
  let parsed = @testkit.run_matches(
    argv=["--max-steps", "25", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_true(@options.max_steps(parsed) is Some(25))
}

///|
test "cli rejects invalid max steps" {
  let parsed = @testkit.run_matches(
    argv=["--max-steps", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = @options.max_steps(parsed) catch {
    error => {
      assert_true("\{error}".contains("--max-steps must be a positive integer"))
      return
    }
  }
  fail("invalid max steps parsed")
}

///|
test "cli parses review deadline option" {
  let parsed = @testkit.run_matches(
    argv=["--review-deadline", "60000", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_true(@options.review_deadline_ms(parsed) is Some(60000))
}

///|
test "cli defaults review deadline to none" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(@options.review_deadline_ms(parsed) is None)
}

///|
test "cli rejects invalid review deadline" {
  let parsed = @testkit.run_matches(
    argv=["--review-deadline", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = @options.review_deadline_ms(parsed) catch {
    error => {
      assert_true(
        "\{error}".contains("--review-deadline must be a positive integer"),
      )
      return
    }
  }
  fail("invalid review deadline parsed")
}

///|
test "ambient OPENSEEK_API_KEY never outranks provider keys for built-in models" {
  let env_only = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "ds-key",
    "OPENSEEK_API_KEY": "custom-key",
  })
  let ds : @deepseek.Model = Deepseek(V4Flash)
  assert_eq(@cli.resolve_api_key(ds, env_only), Some("ds-key"))
  // An explicit --api-key flag still wins over the provider variable.
  let explicit = @testkit.run_matches(
    argv=["--api-key", "flag-key", "write", "MoonBit"],
    env={ "DEEPSEEK": "ds-key", "OPENSEEK_API_KEY": "custom-key" },
  )
  assert_eq(@cli.resolve_api_key(ds, explicit), Some("flag-key"))
  // Custom models still read OPENSEEK_API_KEY from the environment.
  let custom = @deepseek.Model::parse("gemini-4-hydrogen")
  assert_eq(@cli.resolve_api_key(custom, env_only), Some("custom-key"))
}
