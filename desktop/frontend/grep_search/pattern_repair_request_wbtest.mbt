///|
test "pattern repair carries model and thinking through the request codec" {
  let input : Input = {
    owner: Host({ channel: @interop.ChannelId::Local, session: "repair", }),
    cloud_access: None,
    root: Some(@common.Uri::parse("file:///work")),
    model: "glm-5.3",
    thinking: Some(ThinkingMax),
  }
  let state = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg)"), input)
    .handle(FixPattern, input)
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

///|
test "repair completion is pure, ignores stale replies, and preserves outcomes" {
  let input : Input = {
    owner: Host({ channel: @interop.ChannelId::Local, session: "repair", }),
    cloud_access: None,
    root: Some(@common.Uri::parse("file:///work")),
    model: "glm-5.3",
    thinking: None,
  }
  let requested = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "broken"), input)
    .handle(FixPattern, input)
  let generation = requested.page.generation
  let root = input.root_text()
  let statuses : Array[@protocol.PatternRepairStatus] = [
    Passed,
    Unavailable,
    TimedOut,
    Failed,
  ]
  for status in statuses {
    let reply : @protocol.PatternRepairReply = {
      root,
      generation,
      validation_status: status,
      candidate_pattern: Some("inspect($_)"),
      message: "repair diagnostic",
      trace: ["Agent step 1"],
    }
    let msg = PatternRepairFinished(root~, generation~, reply=Some(reply))
    let result = requested.handle(msg, input)
    assert_true(result.page == requested.handle(msg, input).page)
    assert_eq(requested.page.semantic.patterns, ["broken"])
    assert_true(requested.page.pattern_repair_phase is PatternRepairRequested)
    assert_true(result.handle(msg, input).page == result.page)
    let stale = PatternRepairFinished(
      root~,
      generation=generation - 1,
      reply=Some(reply),
    )
    assert_true(requested.handle(stale, input).page == requested.page)
    let other_root = PatternRepairFinished(
      root="/other",
      generation~,
      reply=Some(reply),
    )
    assert_true(requested.handle(other_root, input).page == requested.page)
    if status is Passed {
      assert_eq(result.page.semantic.patterns, ["inspect($_)"])
      assert_true(result.page.phase is Loading)
      assert_true(result.page.pattern_repair_phase is PatternRepairIdle)
    } else {
      assert_eq(result.page.semantic.patterns, ["broken"])
      assert_eq(result.page.pattern_repair_trace, reply.trace)
      assert_eq(
        result.page.pattern_repair_phase,
        match status {
          Unavailable => PatternRepairUnavailable
          TimedOut => PatternRepairTimedOut
          _ => PatternRepairValidationFailed
        },
      )
      assert_eq(
        result.page.pattern_repair_message,
        if status is TimedOut {
          None
        } else {
          Some(reply.message)
        },
      )
      assert_eq(
        result.page.pattern_repair_candidate,
        if status is TimedOut {
          None
        } else {
          reply.candidate_pattern
        },
      )
    }
  }
  let failed = requested.handle(
    PatternRepairFinished(root~, generation~, reply=None),
    input,
  )
  assert_true(failed.page.pattern_repair_phase is PatternRepairFailed)
  assert_eq(failed.page.semantic.patterns, ["broken"])
}
