///|
test "host requests omit missing optionals and reject malformed known fields" {
  for input in [Json::empty_object(), { "run_id": null }, { "future": true }] {
    let payload : @protocol.CancelPayload = @json.from_json(input)
    assert_true(payload.run_id is None)
    assert_eq(payload.to_json(), Json::empty_object())
  }
  let payload : @protocol.CancelPayload = @json.from_json({ "run_id": "run-1" })
  assert_eq(payload.to_json(), { "run_id": "run-1" })
  for input in [Json({ "run_id": 42 }), Json::null(), []] {
    let rejected = try {
      let _ : @protocol.CancelPayload = @json.from_json(input)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "host notifications exclude desktop login and update state" {
  for name in ["auth.changed", "update.download_progress", "app.info"] {
    assert_true(@protocol.HostNotification::from_wire(name, {}) is None)
    assert_false(
      @protocol.HostNotificationKind::all().any(kind => kind.wire_name() == name),
    )
  }
  let event = @protocol.HostNotification::from_wire("terminal.exit", {
    "id": "pty-1",
    "code": 0,
  })
  guard event is Some(event) else { fail("terminal event rejected") }
  assert_eq(event.params(), { "id": "pty-1", "code": 0 })
}
