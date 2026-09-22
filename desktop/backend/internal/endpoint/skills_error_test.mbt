///|
suberror RegistryFailure {
  RegistryFailure(String)
}

///|
impl Show for RegistryFailure with fn output(self, logger) {
  match self {
    RegistryFailure(message) => logger.write_string(message)
  }
}

///|
async test "skill failures cross the endpoint as detailed replies" {
  let message = "GET https://assets.mooncakes.io/api/v0/skills returned HTTP 404"
  let endpoint = @endpoint.Endpoint::skills(@commands.skills_catalog, _ => {
    raise RegistryFailure(message)
  })
  let reply = endpoint.invoke({}) catch {
    _ =>
      fail("skill error escaped the endpoint and would be redacted by Proton")
  }
  assert_eq(reply, { "error": Json(message) })
}
