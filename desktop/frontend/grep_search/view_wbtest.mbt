///|
#warnings("-alert_unstable")
fn render_search(state : State, input : Input) -> String {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      state.explorer_view(input, emit, (_, _) => @cmd.none),
    )
  })
}

///|
test "Search renders VS Code's Whole Word codicon instead of a text label" {
  let input : Input = {
    owner: { channel: @interop.ChannelId::Local, session: "icons", },
    root: Some(@common.Uri::parse("file:///work")),
  }
  let html = render_search(State::empty(), input)
  assert_true(html.contains("aria-label=\"Match Whole Word\""))
  assert_true(html.contains("M15.5 12.5C15.776 12.5"))
  assert_false(html.contains(">ab</button>"))
}

///|
test "Code search renders the pattern repair placeholder only in semantic mode" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "pattern-repair",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let text_html = render_search(State::empty(), input)
  assert_false(text_html.contains("Fix Pattern"))
  let semantic = State::empty().handle(ModeChanged(Semantic), input)
  let requested = semantic.handle(FixPattern, input)
  let requested_html = render_search(requested, input)
  assert_true(requested_html.contains("PATTERN REPAIR"))
  assert_true(requested_html.contains("Pattern repair instruction"))
  assert_true(requested_html.contains("Submit pattern repair"))
  let collapsed = requested.handle(RejectPatternRepair, input)
  assert_false(render_search(collapsed, input).contains("PATTERN REPAIR"))
  let reopened = collapsed.handle(FixPattern, input)
  assert_true(render_search(reopened, input).contains("PATTERN REPAIR"))
  let submitted = requested
    .handle(PatternRepairInstructionChanged("allow labelled arguments"), input)
    .handle(SubmitPatternRepair, input)
  let thinking_html = render_search(submitted, input)
  assert_true(thinking_html.contains("Thinking"))
  let previewed = submitted.handle(
    PatternRepairPreview(
      root=root.path,
      generation=submitted.page.generation,
      candidate_pattern="inspect($_)",
      validation_status="unavailable",
      message="Candidate Pattern is ready for review.",
    ),
    input,
  )
  let preview_html = render_search(previewed, input)
  assert_true(previewed.page.semantic.patterns[0] != "inspect($_)")
  assert_true(preview_html.contains("SUGGESTED PATTERN"))
  assert_true(preview_html.contains("Validation unavailable"))
  let accepted = previewed.handle(AcceptPatternRepair, input)
  assert_true(accepted.page.semantic.patterns[0] == "inspect($_)")
  let discarded = previewed.handle(RejectPatternRepair, input)
  assert_true(discarded.page.semantic.patterns[0] != "inspect($_)")
  let failed = semantic
    .handle(FixPattern, input)
    .handle(PatternRepairInstructionChanged("repair it"), input)
    .handle(SubmitPatternRepair, input)
    .handle(
      PatternRepairFailed(
        root=root.path,
        generation=semantic.page.generation,
        candidate_pattern="match $_ { $$$cases }",
        validation_status="failed",
        message="Fake repair failed.",
      ),
      input,
    )
  let failed_html = render_search(failed, input)
  assert_true(failed_html.contains("Fake repair failed."))
  assert_true(failed_html.contains("Validation failed"))
  assert_true(failed_html.contains("match $_ { $$$cases }"))
  let cancelled = requested.handle(RejectPatternRepair, input)
  let cancelled_html = render_search(cancelled, input)
  assert_false(cancelled_html.contains("PATTERN REPAIR"))
  assert_true(cancelled_html.contains("aria-label=\"Fix Pattern\""))
}

///|
test "Search view groups files and marks matching UTF-16 slices" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "view",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
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
test "large Search replies render incrementally without changing totals" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "large-view",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
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
    matches: Array::make(501, result),
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
  assert_true(initial.contains("501 results in 1 files"))
  assert_true(initial.contains("Show 1 more matching lines"))
  assert_true(initial.contains("500 of 501 matching lines rendered"))
  assert_eq(initial.split("class=\"search-result-row\"").length(), 501)
  let expanded = render_search(ready.handle(ShowMore, input), input)
  assert_false(expanded.contains("search-show-more"))
  assert_eq(expanded.split("class=\"search-result-row\"").length(), 502)
}
