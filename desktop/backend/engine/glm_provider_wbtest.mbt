///|
test "official providers reject models from another provider" {
  let mismatched = try key_env_for(Glm, Deepseek(V4Pro)) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(mismatched.contains("configured GLM provider"))
  assert_eq(key_env_for(Glm, Glm(G53)), "GLM")
  assert_eq(key_env_for(Glm, Glm(G53Flash)), "GLM")
  assert_eq(key_env_for(Deepseek, Deepseek(V4Pro)), "DEEPSEEK")
  // A custom endpoint deliberately follows the selected model family.
  assert_eq(key_env_for(Custom, Glm(G53)), "GLM")
  assert_eq(key_env_for(Custom, Kimi(K27Code)), "KIMI")
  assert_eq(key_env_for(Custom, Deepseek(V4Flash)), "DEEPSEEK")
}
