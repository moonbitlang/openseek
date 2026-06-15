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
test "official endpoint still uses DEEPSEEK env fallback" {
  assert_eq(
    configured_api_key(None, None, Some("official-key")),
    "official-key",
  )
  let _ = configured_api_key(None, None, None) catch {
    HostError(message) => {
      assert_true(message.contains("DeepSeek API key is required"))
      return
    }
  }
  fail("official endpoint accepted a missing key")
}
