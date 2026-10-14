///|
test "edit payloads preserve receipt identity and explicit first-message absence" {
  let first : @protocol.SessionEditPreparePayload = {
    session: "source",
    workspace: "/work",
    through: None,
    model: "deepseek-flash",
    source_title: "Original",
  }
  assert_eq(@json.from_json(first.to_json()), first)
  assert_true(
    first.to_json() is Object(fields) && fields.get("through") is None,
  )
  let later = { ..first, through: Some(3), }
  assert_eq(@json.from_json(later.to_json()), later)
  let cleanup : @protocol.SessionEditCommitPayload = {
    session: "source",
    workspace: "/work",
    replacement: "replacement",
    submission_id: "receipt-1",
    source_sequence: 8,
  }
  assert_eq(@json.from_json(cleanup.to_json()), cleanup)
  let malformed : Array[Json] = [
    {
      "session": "source",
      "workspace": "/work",
      "replacement": "copy",
      "source_sequence": 8,
    },
    {
      "session": "source",
      "workspace": "/work",
      "replacement": "copy",
      "submission_id": null,
      "source_sequence": 8,
    },
    {
      "session": "source",
      "workspace": "/work",
      "replacement": "copy",
      "submission_id": "receipt",
      "source_sequence": "8",
    },
  ]
  for invalid in malformed {
    try (@json.from_json(invalid) : @protocol.SessionEditCommitPayload) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed edit receipt")
    }
  }
}
