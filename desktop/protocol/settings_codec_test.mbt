///|
test "settings patches preserve optional GLM fields and omit absence" {
  let patch : @protocol.SettingsSetPayload = @json.from_json({
    "provider": "glm",
    "providers": { "glm": { "api_url": null, "api_key": "glm-secret" } },
    "prompt_source": "custom",
    "future_field": true,
  })
  assert_eq(patch.provider, Some("glm"))
  assert_eq(patch.providers.unwrap()["glm"].api_key, Some("glm-secret"))
  @debug.assert_eq(patch.to_json(), {
    "provider": "glm",
    "providers": { "glm": { "api_key": "glm-secret" } },
    "prompt_source": "custom",
  })
  let text : @protocol.SettingsSetPayload = @json.from_json({
    "custom_prompt": "",
  })
  assert_eq(text.custom_prompt, Some(""))
  @debug.assert_eq(text.to_json(), { "custom_prompt": "" })
}

///|
test "settings status preserves and requires the GLM capability flag" {
  let status : @protocol.SettingsStatusPayload = @json.from_json({
    "revision": 8,
    "provider": "glm",
    "providers": { "glm": { "has_api_key": true } },
    "followup_behavior": "queue",
    "prompt_source": "custom",
    "custom_prompt": "  Rules\n中文\n",
    "future_field": true,
  })
  assert_true(status.providers["glm"].has_api_key)
  @debug.assert_eq(status.to_json(), {
    "revision": 8,
    "provider": "glm",
    "providers": { "glm": { "has_api_key": true } },
    "followup_behavior": "queue",
    "prompt_source": "custom",
    "custom_prompt": "  Rules\n中文\n",
  })
  let missing : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "providers": { "glm": {} },
      "followup_behavior": "steer",
      "prompt_source": "custom",
      "custom_prompt": "",
    }),
  ) catch {
    _ => None
  }
  assert_true(missing is None)
  let missing_followup : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "providers": { "glm": { "has_api_key": true } },
    }),
  ) catch {
    _ => None
  }
  assert_true(missing_followup is None)
  let malformed : @protocol.SettingsStatusPayload? = Some(
    @json.from_json({
      "revision": 8,
      "provider": "glm",
      "providers": { "glm": { "has_api_key": "yes" } },
      "followup_behavior": "steer",
      "prompt_source": "custom",
      "custom_prompt": "",
    }),
  ) catch {
    _ => None
  }
  assert_true(malformed is None)
}

///|
test "settings patches carry model upserts and removals in one ordered list" {
  let patch : @protocol.SettingsSetPayload = @json.from_json({
    "models": [
      { "id": " old-id ", "removed": true },
      { "id": "new-id", "label": "New", "context_window": 32768 },
    ],
    "future_field": true,
  })
  guard patch.models is Some(entries) else { fail("models must decode") }
  // The id is the key the host matches on, so it is trimmed on the way in.
  assert_eq(entries[0].id, "old-id")
  assert_eq(entries[0].removed, Some(true))
  // An edit states no removal at all, so absence stays absence on the way out.
  assert_eq(entries[1].removed, None)
  assert_eq(entries[1].context_window, Some(32768))
  @debug.assert_eq(patch.to_json(), {
    "models": [
      { "id": "old-id", "removed": true },
      { "id": "new-id", "label": "New", "context_window": 32768 },
    ],
  })
}
