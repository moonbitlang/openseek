///|
test "single edit payload preserves the message and optional fork boundary" {
  let first : @protocol.SessionEditPayload = {
    session: "source",
    workspace: "/work",
    through: None,
    model: "deepseek-flash",
    source_title: "Original",
    source_sequence: 8,
    task: "Revised",
    images: ["data:image/png;base64,aW1hZ2U="],
    attachment_paths: [".openseek/attachments/upload/report.pdf"],
    thinking: None,
    max_steps: None,
  }
  assert_eq(@json.from_json(first.to_json()), first)
  assert_true(
    first.to_json() is Object(fields) && fields.get("through") is None,
  )
  let later = { ..first, through: Some(3), max_steps: Some(100), }
  assert_eq(@json.from_json(later.to_json()), later)
  for field in ["session", "workspace", "task", "images", "source_sequence"] {
    guard first.to_json() is Object(fields) else { fail("object") }
    ignore(fields.remove(field))
    try (@json.from_json(Json(fields)) : @protocol.SessionEditPayload) catch {
      _ => ()
    } noraise {
      _ => fail("accepted incomplete edit")
    }
  }
}
