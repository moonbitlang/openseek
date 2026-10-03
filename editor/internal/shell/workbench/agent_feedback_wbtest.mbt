///|
test "feedback persistence preserves absent empty and verbatim selection snapshots" {
  let resource = @base_common.Uri::file("/workspace/README.md")
  let selections : Array[String?] = [
    None,
    Some(""),
    Some("  selected <words>\nnext line  "),
  ]
  for selected_text in selections {
    let item : @agent_feedback_api.AgentFeedback = {
      id: "feedback-1",
      text: "make this clearer",
      resource,
      range: Range(3, 1, 6, 40),
      selected_text,
      kind: UserReview,
      replies: [],
      state: Accepted,
    }
    let encoded = feedback_item_to_json(item)
    guard encoded is Object(fields) else {
      fail("expected a persisted feedback object")
    }
    assert_eq(
      fields.get("selected_text"),
      selected_text.map(text => text.to_json()),
    )
    guard feedback_item_from_json(resource, encoded) is Some(restored) else {
      fail("expected valid persisted feedback to be restored")
    }
    assert_eq(restored.selected_text, selected_text)
    assert_eq(restored.text, item.text)
    assert_eq(restored.range, item.range)
  }
}

///|
test "feedback persistence rejects a malformed selection snapshot" {
  let resource = @base_common.Uri::file("/workspace/README.md")
  for invalid in [Json::null(), Json(42), Json(true)] {
    let encoded : Json = {
      "text": "note",
      "range": [3, 1, 6, 40],
      "selected_text": invalid,
    }
    assert_true(feedback_item_from_json(resource, encoded) is None)
  }
}
