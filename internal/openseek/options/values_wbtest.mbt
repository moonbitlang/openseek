///|
/// The DeepSeek flash tier's canonical wire name is `deepseek-flash`; the
/// retired `deepseek-v4-flash` name is accepted as an alias for the same tier.
test "cli accepts the canonical flash wire name" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_MODEL": "deepseek-flash",
  })
  let (model, thinking, api_url) = agent_settings(parsed)
  assert_true(model is Deepseek(V4Flash))
  assert_eq(model.to_string(), "deepseek-flash")
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  assert_true(thinking is High)
  assert_true(api_url is None)
}

///|
/// A run pointed at a custom endpoint reads its model from that endpoint: an
/// unknown name becomes a custom model there, and its key travels in the
/// variable the engine's own lookup reads.
test "cli accepts a custom model only beside an explicit endpoint" {
  let custom = @testkit.run_matches(
    argv=[
      "--api-url", "https://proxy.example/v1/chat/completions", "--model", "qwen3-coder",
      "write", "MoonBit",
    ],
    env={ "DEEPSEEK": "proxy-key" },
  )
  let (model, _, api_url) = agent_settings(custom)
  assert_true(model is Custom("qwen3-coder"))
  assert_eq(model.to_string(), "qwen3-coder")
  assert_eq(api_url, Some("https://proxy.example/v1/chat/completions"))
  assert_eq(model.api_key(custom.values), Some("proxy-key"))
  // A custom id whose prefix resembles another provider keeps that provider's
  // variable, exactly as the engine's lookup and the Desktop's routing do.
  let glm_like = @testkit.run_matches(
    argv=[
      "--api-url", "https://proxy.example/v1/chat/completions", "--model", "glm-4.6",
      "write", "MoonBit",
    ],
    env={ "GLM": "proxy-key", "DEEPSEEK": "wrong-key" },
  )
  let (glm_model, _, _) = agent_settings(glm_like)
  assert_true(glm_model is Custom("glm-4.6"))
  assert_eq(glm_model.api_key(glm_like.values), Some("proxy-key"))
  // Without an endpoint the same name stays an error, so a typo cannot
  // silently become a model id.
  let bare = @testkit.run_matches(
    argv=["--model", "qwen3-coder", "write", "MoonBit"],
    env={ "DEEPSEEK": "proxy-key" },
  )
  let detail = try {
    ignore(agent_settings(bare))
    ""
  } catch {
    error => "\{error}"
  } noraise {
    _ => ""
  }
  assert_true(detail.contains("unknown model: qwen3-coder"))
}

///|
test "cli retry flags override the environment and reject non-positives" {
  let parsed = @testkit.run_matches(
    argv=["--retry-attempts", "2", "--retry-backoff-ms", "7", "write"],
    env={ "DEEPSEEK": "test-key", "OPENSEEK_RETRY_ATTEMPTS": "9" },
  )
  assert_eq(retry_overrides(parsed), (Some(2), Some(7)))
  // Rejection is checked through the environment: argparse refuses a bare
  // `-1` as a missing value before the parsed string ever reaches here.
  for bad in ["0", "-1", "many"] {
    let rejected = @testkit.run_matches(argv=["write"], env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_RETRY_ATTEMPTS": bad,
    })
    try ignore(retry_overrides(rejected)) catch {
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
  export_retry_overrides(parsed)
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_ATTEMPTS"), Some("3"))
  assert_eq(@env.get_env_var("OPENSEEK_RETRY_BACKOFF_MS"), Some("11"))
  @env.unset_env_var("OPENSEEK_RETRY_ATTEMPTS")
  @env.unset_env_var("OPENSEEK_RETRY_BACKOFF_MS")
  // Nothing to carry means nothing written: a child keeps falling back to the
  // client default rather than being pinned to a value nobody asked for.
  let bare = @testkit.run_matches(argv=["write"], env={ "DEEPSEEK": "test-key" })
  export_retry_overrides(bare)
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
  assert_eq(kimi_model.api_key(kimi.values), Some("kimi-key"))
  let glm = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "GLM": "glm-key",
    "OPENSEEK_MODEL": "glm-5.3-flash",
  })
  let glm_model : @deepseek.Model = Glm(G53Flash)
  assert_eq(glm_model.api_key(glm.values), Some("glm-key"))
  let deepseek = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "KIMI": "kimi-key",
    "GLM": "glm-key",
  })
  // Provider keys are not fallbacks for a DeepSeek model: no arm matches, so
  // the caller sees `None` and reports it.
  let deepseek_model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(deepseek_model.api_key(deepseek.values) is None)
}

///|
test "agent runs require api key" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env=Map([]))
  let model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(model.api_key(parsed.values) is None)
}

///|
test "agent runs require task text" {
  let parsed = @testkit.run_matches(argv=[], env={ "DEEPSEEK": "test-key" })
  let _ = task_text(parsed) catch {
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
  assert_true(max_steps(parsed) is Some(25))
}

///|
test "cli rejects invalid max steps" {
  let parsed = @testkit.run_matches(
    argv=["--max-steps", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = max_steps(parsed) catch {
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
  assert_true(review_deadline_ms(parsed) is Some(60000))
}

///|
test "cli defaults review deadline to none" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(review_deadline_ms(parsed) is None)
}

///|
test "cli rejects invalid review deadline" {
  let parsed = @testkit.run_matches(
    argv=["--review-deadline", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = review_deadline_ms(parsed) catch {
    error => {
      assert_true(
        "\{error}".contains("--review-deadline must be a positive integer"),
      )
      return
    }
  }
  fail("invalid review deadline parsed")
}
