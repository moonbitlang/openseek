///|
test "pattern repair carries model and thinking through the request codec" {
  let input : Input = {
    owner: { channel: Local, session: "repair", },
    root: Some(@common.Uri::parse("file:///work")),
    model: "glm-5.3",
    thinking: Some(ThinkingMax),
  }
  let state = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(OpenPatternRepair("allow labelled arguments"), input)
    .handle(SubmitPatternRepair, input)
  guard state.page.pattern_repair_request_payload(input) is Some(request) else {
    fail("submitted repair must produce a request")
  }
  let decoded : @protocol.PatternRepairPayload = @json.from_json(
    request.to_json(),
  )
  assert_eq(decoded.model, input.model)
  assert_eq(decoded.thinking, input.thinking)
  let without_thinking = { ..request, thinking: None, }
  let decoded : @protocol.PatternRepairPayload = @json.from_json(
    without_thinking.to_json(),
  )
  assert_eq(decoded.thinking, None)
}
