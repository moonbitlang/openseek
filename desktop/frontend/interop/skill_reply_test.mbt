///|
async test "skill reply errors reach the frontend with their original detail" {
  let original : @js.Value = @js.globalThis.get_with_string("__MoonBit__")
  defer @js.globalThis.set_with_string("__MoonBit__", original)
  let root = @js.Object::new().to_value()
  let api = @js.Object::new().to_value()
  let message = "GET https://assets.mooncakes.io/api/v0/skills returned HTTP 404"
  let failure = @js.Value::from_json({ "error": Json(message) })
  api.set_with_string("skills.catalog", (_ : @js.Value) => failure)
  root.set_with_string("openseek", api)
  @js.globalThis.set_with_string("__MoonBit__", root)
  let failure_reply = @interop.bridge_request(
    Local,
    @commands.skills_catalog,
    NoPayload,
  )
  assert_true(failure_reply is SkillsCatalogError(detail) && detail == message)
  let success = @js.Value::from_json({ "skills": [] })
  api.set_with_string("skills.catalog", (_ : @js.Value) => success)
  let reply = @interop.bridge_request(
    Local,
    @commands.skills_catalog,
    NoPayload,
  )
  assert_true(reply is SkillsCatalog([]))
}
