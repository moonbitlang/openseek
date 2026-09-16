///|
#warnings("-alert_unstable")
#cfg(not(target="js"))
fn render_search(state : State, input : Input) -> String {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  @vdom.server_side_render(() => {
    state.explorer_view(input, emit, (_, _) => @cmd.none).to_virtual_dom()
  })
}

///|
#cfg(not(target="js"))
test "Search renders VS Code's Whole Word codicon instead of a text label" {
  let input : Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner: { channel: @interop.ChannelId::Local, session: "icons", },
    root: Some(@common.Uri::parse("file:///work")),
  }
  let html = render_search(State::empty(), input)
  assert_true(html.contains("aria-label=\"Match Whole Word\""))
  assert_true(html.contains("M15.5 12.5C15.776 12.5"))
  assert_false(html.contains(">ab</button>"))
}

///|
#cfg(not(target="js"))
test "Code search repairs one pattern without a composer or preview" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "pattern-repair",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner,
    root: Some(root),
  }
  let text_html = render_search(State::empty(), input)
  assert_false(text_html.contains("Fix Pattern"))
  let semantic = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg"), input)
  let semantic_html = render_search(semantic, input)
  assert_true(semantic_html.contains("aria-label=\"Fix Pattern\""))
  assert_false(semantic_html.contains("Pattern repair instruction"))
  assert_false(semantic_html.contains("Submit pattern repair"))
  let requested = semantic.handle(FixPattern, input)
  let requested_html = render_search(requested, input)
  assert_true(requested_html.contains("Repairing pattern…"))
  assert_true(requested_html.contains("aria-busy=\"true\""))
  let repaired = requested.handle(
    PatternRepaired(
      root=root.path,
      generation=requested.page.generation,
      candidate_pattern="inspect($_)",
    ),
    input,
  )
  assert_true(repaired.page.semantic.patterns[0] == "inspect($_)")
  assert_true(repaired.page.phase is Loading)
  let repaired_html = render_search(repaired, input)
  assert_false(repaired_html.contains("SUGGESTED PATTERN"))
  assert_false(repaired_html.contains("Use pattern"))
  let failed = semantic
    .handle(FixPattern, input)
    .handle(
      PatternRepairFailed(root=root.path, generation=semantic.page.generation),
      input,
    )
  let failed_html = render_search(failed, input)
  assert_true(failed.page.semantic.patterns[0] == "inspect($(x:arg")
  assert_true(failed_html.contains("Pattern repair failed."))
  assert_true(failed_html.contains("aria-label=\"Retry pattern repair\""))
  assert_true(
    failed.handle(FixPattern, input).page.pattern_repair_phase
    is PatternRepairRequested,
  )
  let unavailable = semantic
    .handle(FixPattern, input)
    .handle(
      PatternRepairUnavailable(
        root=root.path,
        generation=semantic.page.generation,
        message="DeepSeek API key is required; add it in Settings or set DEEPSEEK",
      ),
      input,
    )
  let unavailable_html = render_search(unavailable, input)
  assert_true(
    unavailable_html.contains(
      "DeepSeek API key is required; add it in Settings or set DEEPSEEK",
    ),
  )
  let timed_out = semantic
    .handle(FixPattern, input)
    .handle(
      PatternRepairTimedOut(root=root.path, generation=semantic.page.generation),
      input,
    )
  let timed_out_html = render_search(timed_out, input)
  assert_true(
    timed_out_html.contains(
      "Pattern repair timed out while contacting the AI provider.",
    ),
  )
  assert_true(timed_out_html.contains("Retry pattern repair"))
  let validation_failed = semantic
    .handle(FixPattern, input)
    .handle(
      PatternRepairValidationFailed(
        root=root.path,
        generation=semantic.page.generation,
        candidate_pattern=Some("let mut $(name:id) = $(value:exp)"),
        diagnostic="raw moongrep diagnostic: expected a complete expression",
      ),
      input,
    )
  let validation_failed_html = render_search(validation_failed, input)
  assert_true(validation_failed.page.semantic.patterns[0] == "inspect($(x:arg")
  assert_true(
    validation_failed.page.pattern_repair_candidate
    is Some("let mut $(name:id) = $(value:exp)"),
  )
  assert_true(
    validation_failed_html.contains(
      "Pattern repair failed. The current pattern was not changed.",
    ),
  )
  assert_true(validation_failed_html.contains("Show repair details"))
  assert_true(
    validation_failed_html.contains("Candidate pattern (not applied)"),
  )
  assert_true(
    validation_failed_html.contains("let mut $(name:id) = $(value:exp)"),
  )
  assert_true(
    validation_failed_html.contains(
      "raw moongrep diagnostic: expected a complete expression",
    ),
  )
  let invalid = semantic
    .handle(FixPattern, input)
    .handle(
      PatternRepairFailed(
        root=root.path,
        generation=semantic.page.generation,
        message="invalid_pattern: unmatched parenthesis",
      ),
      input,
    )
  let invalid_html = render_search(invalid, input)
  assert_true(
    invalid_html.contains(
      "Pattern repair returned an invalid pattern. The current pattern was not changed; retry.",
    ),
  )
}

///|
#cfg(not(target="js"))
test "Search view groups files and marks matching UTF-16 slices" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "view",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner,
    root: Some(root),
  }
  let state = State::empty()
    .handle(QueryChanged("moon"), input)
    .handle(Submit, input)
  let page = state.page
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    generation: page.generation,
    matches: [
      {
        path: "src/main.mbt",
        line_number: 7,
        preview: "let moon = 1",
        preview_start_column: 1,
        ranges: [{ start_column: 5, end_column: 9, }],
      },
      {
        path: "src/main.mbt",
        line_number: 9,
        preview: "moon()",
        preview_start_column: 1,
        ranges: [{ start_column: 1, end_column: 5, }],
      },
    ],
    match_count: 2,
    file_count: 1,
    limit_hit: true,
    cancelled: false,
    error: None,
  }
  let ready = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation, reply~),
    input,
  )
  let html = render_search(ready, input)
  assert_true(html.contains(">main.mbt</span>"))
  assert_true(html.contains(">src</span>"))
  assert_true(html.contains("search-match-highlight"))
  assert_true(html.contains("first 20,000 matches"))
  assert_true(html.contains("aria-expanded=\"true\""))
}

///|
#cfg(not(target="js"))
test "large Search replies render incrementally without changing totals" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "large-view",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner,
    root: Some(root),
  }
  let state = State::empty()
    .handle(QueryChanged("moon"), input)
    .handle(Submit, input)
  let page = state.page
  let result : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 7,
    preview: "moon",
    preview_start_column: 1,
    ranges: [{ start_column: 1, end_column: 5, }],
  }
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    generation: page.generation,
    matches: Array::makei(501, i => { ..result, line_number: i * 3 + 1, }),
    match_count: 501,
    file_count: 1,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let ready = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation, reply~),
    input,
  )
  let initial = render_search(ready, input)
  assert_true(initial.contains("501 matches in 1 file"))
  assert_true(initial.contains("Show 1 more results"))
  assert_true(initial.contains("500 of 501 results displayed"))
  assert_eq(initial.split("class=\"search-result-row\"").length(), 501)
  let expanded = render_search(ready.handle(ShowMore, input), input)
  assert_false(expanded.contains("search-show-more"))
  assert_eq(expanded.split("class=\"search-result-row\"").length(), 502)
}
