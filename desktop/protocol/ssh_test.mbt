///|
test "SSH profile codec keeps absent identity distinct from malformed identity" {
  let fields : Map[String, Json] = {
    "id": "ssh_test",
    "name": "Test",
    "destination": "alias",
    "launcher": "/bin/openseek",
    "data_dir": "/data",
    "build_id": "workspace",
  }
  let profile : @protocol.SshProfile = @json.from_json(Json(fields))
  assert_eq(profile.server_id, None)
  assert_eq(profile.to_json(), Json(fields))
  fields["server_id"] = (null : Json)
  let profile : @protocol.SshProfile = @json.from_json(Json(fields))
  assert_eq(profile.server_id, None)
  fields["server_id"] = 12
  let rejected = try {
    let _ : @protocol.SshProfile = @json.from_json(Json(fields))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  fields.remove("server_id")
  fields.remove("data_dir")
  let rejected = try {
    let _ : @protocol.SshProfile = @json.from_json(Json(fields))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "SSH outcome codec cannot turn unknown into unsent or omit its payload" {
  for
    reply in [
      @protocol.SshSuccess({ "value": 1 }),
      SshUnsent("offline"),
      SshRefused("draining"),
      SshUnknown("lost"),
    ] {
    let decoded : @protocol.SshReply = @json.from_json(reply.to_json())
    assert_eq(decoded.to_json(), reply.to_json())
  }
  let invalid : Array[Json] = [
    { "outcome": "unknown" },
    { "outcome": "success" },
    { "outcome": "typo", "message": "x" },
  ]
  for value in invalid {
    let rejected = try {
      let _ : @protocol.SshReply = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
