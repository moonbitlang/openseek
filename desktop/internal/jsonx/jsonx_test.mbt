///|
fn fields_of(json : Json) -> Map[String, Json] raise {
  guard json is Object(fields) else { fail("expected a JSON object") }
  fields
}

///|
test "json_text only accepts present strings" {
  let fields = fields_of({ "s": "value", "blank": "", "n": 3, "arr": ["value"] })
  assert_true(@jsonx.json_text(fields, "s") is Some("value"))
  // Present-but-empty is still present; blank policy belongs to callers.
  assert_true(@jsonx.json_text(fields, "blank") is Some(""))
  // Missing or mistyped (the array a mis-encoded Option produces) is None.
  assert_true(@jsonx.json_text(fields, "missing") is None)
  assert_true(@jsonx.json_text(fields, "n") is None)
  assert_true(@jsonx.json_text(fields, "arr") is None)
}

///|
test "json_first_text prefers the current name over the legacy one" {
  let fields = fields_of({ "content": "now", "step": "old" })
  assert_true(@jsonx.json_first_text(fields, "content", "step") is Some("now"))
  assert_true(@jsonx.json_first_text(fields, "reason", "step") is Some("old"))
  assert_true(@jsonx.json_first_text(fields, "reason", "error") is None)
}

///|
test "json_int only accepts present numbers" {
  let fields = fields_of({ "n": 42, "s": "42" })
  assert_true(@jsonx.json_int(fields, "n") is Some(42))
  assert_true(@jsonx.json_int(fields, "s") is None)
  assert_true(@jsonx.json_int(fields, "missing") is None)
}
