///|
test "session fork requires a concrete terminal boundary and workspace" {
  let payload : @protocol.SessionForkPayload = @json.from_json({
    "session": "source",
    "workspace": "/work",
    "through": 4,
    "model": "deepseek-flash",
    "source_title": "自动标题",
    "future_field": true,
  })
  assert_eq(payload.through, 4)
  assert_eq(@json.from_json(payload.to_json()), payload)
  assert_eq(payload.source_title, "自动标题")
  for field in ["session", "workspace", "through", "model", "source_title"] {
    guard payload.to_json() is Object(fields) else { fail("not an object") }
    fields.remove(field)
    let missing : Result[@protocol.SessionForkPayload, @json.JsonDecodeError] = Ok(
      @json.from_json(Json(fields)),
    ) catch {
      error => Err(error)
    }
    assert_true(missing is Err(_))
    fields[field] = Json::null()
    let null_value : Result[@protocol.SessionForkPayload, @json.JsonDecodeError] = Ok(
      @json.from_json(Json(fields)),
    ) catch {
      error => Err(error)
    }
    assert_true(null_value is Err(_))
  }
}
