///|
async test "skill content returns its error through a normal reply" {
  let reply = @skills.installed_content({ id: "../invalid", })
  assert_true(reply is SkillContentError("invalid skill id: ../invalid"))
  assert_eq(reply.to_json(), { "error": "invalid skill id: ../invalid" })
}

///|
async test "enablement returns library errors as typed replies" {
  let reply = @skills.set_enabled({ id: "../invalid", enabled: false, }, () => {
    ()
  })
  assert_true(reply is SkillEnabledError("invalid skill id: ../invalid"))
  assert_eq(reply.to_json(), { "error": "invalid skill id: ../invalid" })
}
