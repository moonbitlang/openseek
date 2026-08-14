///|
test "official providers reject models from another provider" {
  let mismatched = try key_env_for(Glm, "deepseek-v4-pro") catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(mismatched.contains("configured GLM provider"))
  assert_eq(key_env_for(Glm, "glm-5.3"), "GLM")
  assert_eq(key_env_for(Glm, "glm-5.3-flash"), "GLM")
  assert_eq(key_env_for(Deepseek, "deepseek-v4-pro"), "DEEPSEEK")
  // A custom endpoint deliberately follows the selected model family.
  assert_eq(key_env_for(Custom, "glm-5.3"), "GLM")
  assert_eq(key_env_for(Custom, "kimi-k2.7-code"), "KIMI")
  assert_eq(key_env_for(Custom, "deepseek-v4-flash"), "DEEPSEEK")
  assert_eq(key_env_for(Custom, "some-proxy-model"), "DEEPSEEK")
}
