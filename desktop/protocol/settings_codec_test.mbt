///|
test "settings patches preserve optional GLM fields and omit absence" {
  let patch : @protocol.SettingsSetPayload = @json.from_json({
    "provider": "glm",
    "custom_api_url": null,
    "deepseek_api_key": null,
    "glm_api_key": "glm-secret",
    "future_field": true,
  })
  assert_eq(patch.provider, Some("glm"))
  assert_eq(patch.glm_api_key, Some("glm-secret"))
  @debug.assert_eq(patch.to_json(), {
    "provider": "glm",
    "glm_api_key": "glm-secret",
  })
}

///|
test "settings status preserves and requires the GLM capability flag" {
  let status : @protocol.SettingsStatusPayload = @json.from_json({
    "revision": 8,
    "provider": "glm",
    "custom_api_url": null,
    "has_deepseek_key": false,
    "has_glm_key": true,
    "has_custom_key": false,
    "followup_behavior": "queue",
    "future_field": true,
  })
  assert_true(status.has_glm_key)
  @debug.assert_eq(status.to_json(), {
    "revision": 8,
    "provider": "glm",
    "has_deepseek_key": false,
    "has_glm_key": true,
    "has_custom_key": false,
    "followup_behavior": "queue",
  })
  let missing : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "has_deepseek_key": false,
      "has_custom_key": false,
    }),
  ) catch {
    _ => None
  }
  assert_true(missing is None)
  let missing_followup : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "has_deepseek_key": false,
      "has_glm_key": true,
      "has_custom_key": false,
    }),
  ) catch {
    _ => None
  }
  assert_true(missing_followup is None)
  let malformed : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "has_deepseek_key": false,
      "has_glm_key": "yes",
      "has_custom_key": false,
    }),
  ) catch {
    _ => None
  }
  assert_true(malformed is None)
}
