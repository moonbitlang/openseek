///|
#warnings("-alert_unstable")
#cfg(not(target="js"))
fn render_search(state : State, input : @grep_search.Input) -> String {
  let emit : @cmd.Emit[@grep_search.Msg] = @cmd.Emit(_ => @cmd.none)
  @vdom.server_side_render(() => {
    state.explorer_view(input, emit, (_, _) => @cmd.none).to_virtual_dom()
  })
}

///|
#cfg(not(target="js"))
test "Search renders VS Code's Whole Word codicon instead of a text label" {
  let input : @grep_search.Input = {
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
test "Search view groups files and marks matching UTF-16 slices" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "view",
  }
  let root = @common.Uri::parse("file:///work")
  let input : @grep_search.Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner,
    root: Some(root),
  }
  let state = State::empty()
    .handle(@grep_search.QueryChanged("moon"), input)
    .handle(@grep_search.Submit, input)
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
    @grep_search.Loaded(
      owner~,
      root=root.path,
      generation=page.generation,
      reply~,
    ),
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
  let input : @grep_search.Input = {
    model: "deepseek-v4-flash",
    thinking: Some(ThinkingHigh),
    owner,
    root: Some(root),
  }
  let state = State::empty()
    .handle(@grep_search.QueryChanged("moon"), input)
    .handle(@grep_search.Submit, input)
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
    @grep_search.Loaded(
      owner~,
      root=root.path,
      generation=page.generation,
      reply~,
    ),
    input,
  )
  let initial = render_search(ready, input)
  assert_true(initial.contains("501 matches in 1 file"))
  assert_true(initial.contains("Show 1 more results"))
  assert_true(initial.contains("500 of 501 results displayed"))
  assert_eq(initial.split("class=\"search-result-row\"").length(), 501)
  let expanded = render_search(
    ready.handle(@grep_search.ShowMore, input),
    input,
  )
  assert_false(expanded.contains("search-show-more"))
  assert_eq(expanded.split("class=\"search-result-row\"").length(), 502)
}
