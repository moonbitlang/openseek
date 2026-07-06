///|
test "a different endpoint cannot reuse a live engine process" {
  let base : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "deepseek-v4-pro",
    max_steps: 1000,
    engine: "openseek",
    host: Native,
    cwd: None,
    session: None,
    session_root: None,
  }
  let custom = {
    ..base,
    api_url: Some("https://proxy.example/chat/completions"),
  }
  assert_true(engine_fingerprint(base) != engine_fingerprint(custom))
  assert_eq(engine_fingerprint(base), engine_fingerprint({ ..base, task: "u" }))
}

///|
test "switching engine hosts cannot reuse a live engine process" {
  let base : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "deepseek-v4-pro",
    max_steps: 1000,
    engine: "openseek",
    host: Native,
    cwd: None,
    session: None,
    session_root: None,
  }
  let wsl = { ..base, host: Wsl(distro=Some("Ubuntu"), engine="openseek") }
  assert_true(engine_fingerprint(base) != engine_fingerprint(wsl))
  assert_true(
    engine_fingerprint(wsl) !=
    engine_fingerprint({
      ..base,
      host: Wsl(distro=Some("Debian"), engine="openseek"),
    }),
  )
}

///|
test "custom endpoint does not reuse DEEPSEEK env fallback" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://proxy.example/chat/completions"),
      Some("official-key"),
    ),
    PlaceholderApiKey,
  )
  assert_eq(
    configured_api_key(
      Some("custom-key"),
      Some("https://proxy.example/chat/completions"),
      Some("official-key"),
    ),
    "custom-key",
  )
}

///|
test "official OpenSeek proxy authenticates with the client token" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      Some("official-key"),
      client_token="stamped-token",
    ),
    "stamped-token",
  )
  // A user-provided key always wins over the stamped token.
  assert_eq(
    configured_api_key(
      Some("user-key"),
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    "user-key",
  )
  // An unstamped build behaves as before.
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      None,
    ),
    PlaceholderApiKey,
  )
}

///|
test "other endpoints never see the client token" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://proxy.example/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    PlaceholderApiKey,
  )
  // A lookalike host on another domain does not match the prefix.
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn.evil.example/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    PlaceholderApiKey,
  )
}

///|
test "official endpoint still uses DEEPSEEK env fallback" {
  assert_eq(
    configured_api_key(None, None, Some("official-key")),
    "official-key",
  )
  let _ = configured_api_key(None, None, None) catch {
    EngineError(message) => {
      assert_true(message.contains("DeepSeek API key is required"))
      return
    }
  }
  fail("official endpoint accepted a missing key")
}

///|
async test "desktop start ignores OPENSEEK_API_URL without an explicit payload URL" {
  let previous = @sys.get_env_var("OPENSEEK_API_URL")
  @sys.set_env_var("OPENSEEK_API_URL", "https://env.example/chat/completions")
  let config = run_config(
    {
      task: "hello",
      api_key: Some("official-key"),
      api_url: None,
      model: None,
      max_steps: None,
      session: None,
      session_root: None,
      workspace: None,
      wsl: None,
    },
    "openseek",
  ) catch {
    error => {
      if previous is Some(value) {
        @sys.set_env_var("OPENSEEK_API_URL", value)
      } else {
        @sys.unset_env_var("OPENSEEK_API_URL")
      }
      raise error
    }
  }
  if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_API_URL", value)
  } else {
    @sys.unset_env_var("OPENSEEK_API_URL")
  }
  assert_true(config.api_url is None)
  assert_eq(config.api_key, "official-key")
}
