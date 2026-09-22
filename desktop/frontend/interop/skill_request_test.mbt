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
  try @interop.skill_request(Local, @commands.skills_catalog, NoPayload) catch {
    error => {
      assert_eq(@interop.bridge_error_text(error), message)
      assert_true(@interop.bridge_failure(error) is Refused)
    }
  } noraise {
    _ => fail("expected the skill reply error")
  }
  let success = @js.Value::from_json({ "skills": [] })
  api.set_with_string("skills.catalog", (_ : @js.Value) => success)
  let reply = @interop.skill_request(Local, @commands.skills_catalog, NoPayload)
  assert_eq(reply.skills.length(), 0)
}
