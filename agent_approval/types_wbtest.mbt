///|
test "a verdict round-trips through its JSON contract" {
  let verdict = { decision: Deny, reason: "target holds uncommitted work", }
  let json = ToJson::to_json(verdict)
  json_inspect(json, content={
    "decision": "deny",
    "reason": "target holds uncommitted work",
  })
  guard Verdict::parse(json) is Ok(parsed) else {
    fail("expected the encoded verdict to parse")
  }
  assert_eq(parsed, verdict)
}

///|
test "a verdict with an unknown decision or a blank reason is refused" {
  guard Verdict::parse({ "decision": "maybe", "reason": "x" }) is Err(message) else {
    fail("an unknown decision should be refused")
  }
  assert_true(message.contains("allow, deny, or escalate"))
  assert_true(Verdict::parse({ "decision": "allow", "reason": "  " }) is Err(_))
  assert_true(Verdict::parse({ "decision": "allow" }) is Err(_))
}

///|
test "a review request carries the ask and the user's messages" {
  let request = ReviewRequest(
    { tool_name: "remove", detail: "build/ (deletion)", body: None, },
    intent=["clean the build output"],
  )
  let json = ToJson::to_json(request)
  json_inspect(json, content={
    "tool_name": "remove",
    "detail": "build/ (deletion)",
    "intent": ["clean the build output"],
  })
  guard ReviewRequest::parse(json) is Ok(parsed) else {
    fail("expected the encoded request to parse")
  }
  assert_eq(parsed, request)
}

///|
test "a review request without a detail is refused" {
  assert_true(
    ReviewRequest::parse({ "tool_name": "mbtx", "detail": "", "intent": [] })
    is Err(_),
  )
  assert_true(ReviewRequest::parse({ "query": "x" }) is Err(_))
}

///|
test "submit_verdict declares itself a control tool" {
  let captured : Ref[Verdict?] = { val: None, }
  assert_true(submit_verdict_tool(captured).is_control())
}
