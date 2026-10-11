///|
test "start and steer payloads preserve submission ids" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "images": [],
    "session": "s-start",
    "submission_id": "submission-start",
    "thinking": "high",
  })
  assert_eq(start.submission_id, Some("submission-start"))
  assert_eq(start.thinking, Some(ThinkingHigh))
  let steer : @protocol.SteerPayload = @json.from_json({
    "text": "more detail",
    "images": [],
    "run_id": "r1",
    "submission_id": "submission-steer",
  })
  assert_eq(steer.submission_id, Some("submission-steer"))
}

///|
test "start and steer payloads may omit submission ids" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "images": [],
    "session": "s-start",
  })
  assert_true(start.submission_id is None)
  let steer : @protocol.SteerPayload = @json.from_json({
    "text": "more detail",
    "images": [],
  })
  assert_true(steer.submission_id is None)
}

///|
test "client-authored session roots are ignored" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "images": [],
    "session": "s-start",
    "session_root": "/client/chosen/store",
  })
  assert_eq(start.session, "s-start")
  assert_true(start.workspace is None)
  let compact : @protocol.CompactPayload = @json.from_json({
    "session": "s-compact",
    "session_root": "/client/chosen/store",
  })
  assert_eq(compact.session, "s-compact")
  assert_true(compact.workspace is None)
}

///|
test "start payload requires a session" {
  let decoded : @protocol.StartPayload? = Some(
    @json.from_json({ "task": "hello", "images": [] }),
  ) catch {
    _ => None
  }
  assert_true(decoded is None)
}

///|
test "goal payload distinguishes set from clear by the text field" {
  let set : @protocol.GoalPayload = @json.from_json({
    "session": "s-goal",
    "text": "ship the feature",
    "model": "deepseek-v4-pro",
    "thinking": "max",
  })
  assert_eq(set.text, Some("ship the feature"))
  assert_eq(set.model, Some("deepseek-v4-pro"))
  assert_eq(set.thinking, Some(ThinkingMax))
  let clear : @protocol.GoalPayload = @json.from_json({ "session": "s-goal" })
  assert_true(clear.text is None)
}
