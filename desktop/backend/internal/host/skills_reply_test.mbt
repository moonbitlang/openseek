///|
async test "skill op returns its error through a normal endpoint reply" {
  let actor = @engine.new_engine_actor("unused-test-engine")
  let endpoints = @host.endpoints(
    @host.new_host_state("unused-test-engine"),
    HostConnection(),
    actor.manager(),
    () => (),
  )
  for endpoint in endpoints {
    if endpoint.name() == "skills.installed_content" {
      let reply = endpoint.invoke({ "id": "../invalid" })
      assert_eq(reply, { "error": "invalid skill id: ../invalid" })
      let decoded : @protocol.SkillContentReply = @json.from_json(reply)
      assert_true(decoded is SkillContentError("invalid skill id: ../invalid"))
      return
    }
  }
  fail("skills.installed_content endpoint was not registered")
}
