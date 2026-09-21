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
  // An absent list is "leave the stored one alone", which is not the same
  // instruction as an empty one.
  assert_true(patch.custom_models is None)
  @debug.assert_eq(patch.to_json(), {
    "provider": "glm",
    "glm_api_key": "glm-secret",
  })
}

///|
test "a settings patch carries a whole custom-model list, empty included" {
  let patch : @protocol.SettingsSetPayload = @json.from_json({
    "custom_models": [
      { "id": "qwen3-coder", "label": "Qwen3 Coder" },
      { "id": "local-llama", "label": null },
    ],
  })
  let models = patch.custom_models.unwrap()
  assert_eq(models.length(), 2)
  assert_eq(models[0].id, "qwen3-coder")
  assert_eq(models[0].label, Some("Qwen3 Coder"))
  assert_true(models[1].label is None)
  @debug.assert_eq(patch.to_json(), {
    "custom_models": [
      { "id": "qwen3-coder", "label": "Qwen3 Coder" },
      { "id": "local-llama" },
    ],
  })
  // A present empty list is the wire's "clear the stored models".
  let cleared : @protocol.SettingsSetPayload = @json.from_json({
    "custom_models": [],
  })
  assert_eq(cleared.custom_models.unwrap().length(), 0)
  @debug.assert_eq(cleared.to_json(), { "custom_models": [] })
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
    "custom_models": [{ "id": "qwen3-coder", "label": "Qwen3 Coder" }],
    "future_field": true,
  })
  assert_true(status.has_glm_key)
  assert_eq(status.custom_models.length(), 1)
  assert_eq(status.custom_models[0].id, "qwen3-coder")
  @debug.assert_eq(status.to_json(), {
    "revision": 8,
    "provider": "glm",
    "has_deepseek_key": false,
    "has_glm_key": true,
    "has_custom_key": false,
    "followup_behavior": "queue",
    "custom_models": [{ "id": "qwen3-coder", "label": "Qwen3 Coder" }],
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
  // The model list is required too: a client that dropped it would show an
  // endpoint with no models rather than the ones the user configured.
  let missing_models : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "has_deepseek_key": false,
      "has_glm_key": true,
      "has_custom_key": false,
      "followup_behavior": "steer",
    }),
  ) catch {
    _ => None
  }
  assert_true(missing_models is None)
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
