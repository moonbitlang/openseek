///|
test "skill command replies preserve errors and reject malformed error fields" {
  let reply : @protocol.SkillCommandReply[@protocol.SkillsCatalogReply] = @json.from_json({
      "error": "HTTP 404",
      "extra": true,
    },
  )
  assert_eq(reply.to_json(), { "error": "HTTP 404" })
  for value in [Json::null(), Json(42)] {
    try {
      let _ : @protocol.SkillCommandReply[@protocol.SkillsCatalogReply] = @json.from_json({
          "error": value,
          "skills": [],
        },
      )
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("malformed errors must not decode as a successful catalog")
    }
  }
}
