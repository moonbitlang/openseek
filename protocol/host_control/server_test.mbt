///|
test "initialize rejects missing and incorrectly typed version fields" {
  for
    value in [
      Json::null(),
      { "build_id": "", "protocol_version": 1 },
      { "build_id": "build" },
      { "build_id": "build", "protocol_version": "1" },
      { "build_id": "build", "protocol_version": 1.5 },
    ] {
    let rejected = try {
      let _ : @host_control.Initialize = @json.from_json(value)
      false
    } catch {
      @json.JsonDecodeError(_) => true
    }
    assert_true(rejected)
  }
  let decoded : @host_control.Initialize = @json.from_json({
    "build_id": "build",
    "protocol_version": 1,
  })
  assert_eq(decoded.build_id, "build")
  assert_eq(decoded.protocol_version, 1)
}

///|
test "shutdown grace has a default and rejects noninteger or out of range values" {
  assert_eq(@host_control.shutdown_grace_seconds({}), 60)
  for n in [0, 300] {
    assert_eq(
      @host_control.shutdown_grace_seconds({ "shutdown_grace_seconds": n }),
      n,
    )
  }
  for value in [Json(-1), 301, 1.5, "60", true] {
    let rejected = try {
      ignore(
        @host_control.shutdown_grace_seconds({ "shutdown_grace_seconds": value }),
      )
      false
    } catch {
      @json.JsonDecodeError(_) => true
    }
    assert_true(rejected)
  }
}
