///|
test "background rendering preference requires an explicit boolean" {
  let invalid : Array[Json] = [{}, { "enabled": null }, { "enabled": "true" }]
  for value in invalid {
    let rejected = try {
      let _ : @protocol.BackgroundRenderingSetPayload = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let preference : @protocol.BackgroundRenderingSetPayload = @json.from_json({
    "enabled": false,
    "future": true,
  })
  assert_false(preference.enabled)
}

///|
test "background rendering preserves pending restart and failure separately" {
  let status : @protocol.BackgroundRenderingSettings = {
    supported: true,
    enabled: false,
    launch_enabled: true,
    error: Some("session failed"),
  }
  let restored : @protocol.BackgroundRenderingSettings = @json.from_json(
    status.to_json(),
  )
  assert_eq(restored, status)
  let healthy : @protocol.BackgroundRenderingSettings = {
    ..status,
    error: None,
  }
  assert_eq(healthy.to_json(), {
    "supported": true,
    "enabled": false,
    "launch_enabled": true,
  })
}
