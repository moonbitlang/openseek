///|
test "official providers reject models from another provider" {
  let mismatched = try key_env_for(Glm, "deepseek-v4-pro", []) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(mismatched.contains("configured GLM provider"))
  assert_eq(key_env_for(Glm, "glm-5.3", []), "GLM")
  assert_eq(key_env_for(Glm, "glm-5.3-flash", []), "GLM")
  assert_eq(key_env_for(Deepseek, "deepseek-v4-pro", []), "DEEPSEEK")
}

///|
test "a custom endpoint routes built-in and configured models" {
  let configured : Array[CustomModel] = [
    { id: "qwen3-coder", label: Some("Qwen3 Coder"), },
    { id: "glm-4.6", label: None, },
    { id: "kimi-k2-thinking", label: None, },
  ]
  // A built-in id keeps its own provider's variable, exactly as the engine
  // parses it.
  assert_eq(key_env_for(Custom, "glm-5.3", configured), "GLM")
  assert_eq(key_env_for(Custom, "kimi-k2.7-code", configured), "KIMI")
  assert_eq(key_env_for(Custom, "deepseek-v4-flash", configured), "DEEPSEEK")
  // A configured id follows its own prefix, which is the variable the engine
  // reads for a model it does not know.
  assert_eq(key_env_for(Custom, "qwen3-coder", configured), "DEEPSEEK")
  assert_eq(key_env_for(Custom, "glm-4.6", configured), "GLM")
  assert_eq(key_env_for(Custom, "kimi-k2-thinking", configured), "KIMI")
}

///|
test "a custom endpoint refuses a model nobody configured" {
  let unconfigured = try {
    ignore(key_env_for(Custom, "some-proxy-model", []))
    ""
  } catch {
    EngineError(message) => message
  }
  assert_true(unconfigured.contains("is not configured for this endpoint"))
  // The same id runs once the user adds it.
  assert_eq(
    key_env_for(Custom, "some-proxy-model", [
      { id: "some-proxy-model", label: None, },
    ]),
    "DEEPSEEK",
  )
}
