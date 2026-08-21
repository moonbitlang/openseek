///|
const SearchDebounceMs : Int = 250

///|
const MaxSearchResults : Int = 20000

///|
fn fresh_page() -> Page {
  {
    mode: Text,
    query: "",
    regex: false,
    case_sensitive: false,
    whole_word: false,
    details_open: false,
    include_glob: "",
    exclude_glob: "",
    rules_dir: "",
    use_builtin_rules: false,
    matches: [],
    semantic_hits: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    collapsed: Map([]),
    visible_lines: InitialVisibleSearchLines,
    phase: Idle,
    generation: 0,
    delay_ms: SearchDebounceMs,
  }
}

///|
/// Retire every query/result derived from the outgoing checkout. The monotonic
/// generation deliberately survives the reset so an A -> B -> A transition
/// cannot make an old reply current again, while the armed Search mode and its
/// semantic settings survive the checkout switch.
pub fn State::reset_checkout(self : State) -> State {
  let generation = self.generation + 1
  {
    page: {
      ..fresh_page(),
      generation,
      mode: self.page.mode,
      rules_dir: self.page.rules_dir,
      use_builtin_rules: self.page.use_builtin_rules,
    },
    generation,
  }
}

///|
fn Input::root_text(self : Input) -> String {
  self.root.map(root => root.path).unwrap_or("")
}

///|
fn State::schedule(
  self : State,
  page : Page,
  input : Input,
  immediate~ : Bool,
) -> State {
  let generation = self.generation + 1
  let page = if page.query.is_empty() || input.root is None {
    {
      ..page,
      matches: [],
      semantic_hits: [],
      match_count: 0,
      file_count: 0,
      limit_hit: false,
      visible_lines: InitialVisibleSearchLines,
      phase: Idle,
      generation,
    }
  } else {
    {
      ..page,
      visible_lines: InitialVisibleSearchLines,
      phase: if immediate {
        Loading
      } else {
        Debouncing
      },
      generation,
      delay_ms: if immediate {
        0
      } else {
        SearchDebounceMs
      },
    }
  }
  { page, generation }
}

///|
/// Park host work because the current checkout disappeared. Ordinary UI
/// visibility changes intentionally do not call this: a search already issued
/// from the Explorer may settle while another inventory or tab is visible.
pub fn State::park(self : State) -> State {
  let page = self.page
  guard page.phase is Debouncing || page.phase is Loading else { return self }
  let generation = self.generation + 1
  { generation, page: { ..page, phase: Idle, generation } }
}

///|
pub fn State::handle(self : State, msg : Msg, input : Input) -> State {
  let page = self.page
  match msg {
    QueryChanged(query) =>
      self.schedule({ ..page, query, }, input, immediate=false)
    ModeChanged(mode) =>
      self.schedule(
        {
          ..page,
          mode,
          matches: [],
          semantic_hits: [],
          collapsed: Map([]),
        },
        input,
        immediate=false,
      )
    ToggleCaseSensitive =>
      self.schedule(
        { ..page, case_sensitive: !page.case_sensitive },
        input,
        immediate=false,
      )
    ToggleWholeWord =>
      self.schedule(
        { ..page, whole_word: !page.whole_word },
        input,
        immediate=false,
      )
    ToggleRegex =>
      self.schedule({ ..page, regex: !page.regex }, input, immediate=false)
    ToggleDetails =>
      { ..self, page: { ..page, details_open: !page.details_open } }
    IncludeChanged(include_glob) =>
      self.schedule({ ..page, include_glob, }, input, immediate=false)
    ExcludeChanged(exclude_glob) =>
      self.schedule({ ..page, exclude_glob, }, input, immediate=false)
    RulesDirChanged(rules_dir) =>
      self.schedule({ ..page, rules_dir, }, input, immediate=false)
    ToggleBuiltinRules =>
      self.schedule(
        { ..page, use_builtin_rules: !page.use_builtin_rules },
        input,
        immediate=false,
      )
    Submit | Refresh => self.schedule(page, input, immediate=true)
    ClearResults => {
      let generation = self.generation + 1
      {
        generation,
        page: {
          ..page,
          matches: [],
          semantic_hits: [],
          match_count: 0,
          file_count: 0,
          limit_hit: false,
          visible_lines: InitialVisibleSearchLines,
          phase: Idle,
          generation,
        },
      }
    }
    CollapseAll => {
      let collapsed : Map[String, Bool] = Map([])
      let active = match page.mode {
        Text => page.matches.map(result => result.path)
        Semantic => page.semantic_hits.map(hit => hit.path)
      }
      for path in active {
        collapsed[path] = true
      }
      { ..self, page: { ..page, collapsed, } }
    }
    ShowMore =>
      {
        ..self,
        page: {
          ..page,
          visible_lines: (page.visible_lines + VisibleSearchLineStep).min(
            page.active_result_count(),
          ),
        },
      }
    ToggleFile(path) => {
      let collapsed = page.collapsed.copy()
      if collapsed.get(path).unwrap_or(false) {
        collapsed.remove(path)
      } else {
        collapsed[path] = true
      }
      { ..self, page: { ..page, collapsed, } }
    }
    RequestStarted(owner~, root~, generation~) =>
      if input.owner == owner &&
        input.root_text() == root &&
        page.generation == generation &&
        page.phase is Debouncing {
        { ..self, page: { ..page, phase: Loading } }
      } else {
        self
      }
    Loaded(owner~, root~, generation~, reply~) => {
      guard input.owner == owner &&
        input.root_text() == root &&
        page.generation == generation &&
        page.mode is Text &&
        reply.root == root &&
        reply.generation == generation else {
        return self
      }
      if reply.cancelled {
        return { ..self, page: { ..page, phase: Idle } }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self,
        page: {
          ..page,
          matches: reply.matches,
          semantic_hits: [],
          match_count: reply.match_count,
          file_count: reply.file_count,
          limit_hit: reply.limit_hit,
          visible_lines: InitialVisibleSearchLines.min(reply.matches.length()),
          phase,
        },
      }
    }
    SemanticLoaded(owner~, root~, generation~, reply~) => {
      guard input.owner == owner &&
        input.root_text() == root &&
        page.generation == generation &&
        page.mode is Semantic &&
        reply.root == root &&
        reply.generation == generation else {
        return self
      }
      if reply.cancelled {
        return { ..self, page: { ..page, phase: Idle } }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self,
        page: {
          ..page,
          matches: [],
          semantic_hits: reply.matches,
          match_count: reply.match_count,
          file_count: reply.file_count,
          limit_hit: reply.limit_hit,
          visible_lines: InitialVisibleSearchLines.min(reply.matches.length()),
          phase,
        },
      }
    }
    RequestFailed(owner~, root~, generation~, code~, message~) =>
      if input.owner == owner &&
        input.root_text() == root &&
        page.generation == generation {
        {
          ..self,
          page: {
            ..page,
            matches: [],
            semantic_hits: [],
            match_count: 0,
            file_count: 0,
            limit_hit: false,
            visible_lines: InitialVisibleSearchLines,
            phase: Failed(code~, message~),
          },
        }
      } else {
        self
      }
  }
}

///|
/// Project the retained Host results for `path` into the editor's one-based
/// UTF-16 coordinate space. OpenSeek's source viewer is read-only, so these
/// ranges stay authoritative for the search snapshot without duplicating
/// ripgrep's regex, case, and whole-word semantics in the frontend.
pub fn State::editor_highlights(
  self : State,
  path : String,
) -> EditorHighlights? {
  guard self.page.phase is Ready else { return None }
  let ranges : Array[@common.Range] = []
  match self.page.mode {
    Text =>
      for result in self.page.matches {
        if result.path == path {
          for range in result.ranges {
            ranges.push(
              @common.Range(
                result.line_number,
                range.start_column,
                result.line_number,
                range.end_column,
              ),
            )
          }
        }
      }
    Semantic =>
      for hit in self.page.semantic_hits {
        if hit.path == path {
          ranges.push(
            @common.Range(
              hit.start_line,
              hit.start_column,
              hit.end_line,
              hit.end_column,
            ),
          )
        }
      }
  }
  guard !ranges.is_empty() else { return None }
  Some({ ranges, })
}

///|
fn Page::active_result_count(self : Page) -> Int {
  match self.mode {
    Text => self.matches.length()
    Semantic => self.semantic_hits.length()
  }
}

///|
fn Page::text_request_payload(
  self : Page,
  input : Input,
) -> @protocol.SearchTextPayload? {
  guard self.mode is Text else { return None }
  guard input.root is Some(root) && !self.query.is_empty() else { return None }
  Some({
    root: root.path,
    query: self.query,
    regex: self.regex,
    case_sensitive: self.case_sensitive,
    whole_word: self.whole_word,
    include_glob: self.include_glob,
    exclude_glob: self.exclude_glob,
    session_key: "grep-search:\{input.owner.channel.uri_authority()}:\{input.owner.session}:\{root.path}",
    generation: self.generation,
    max_results: MaxSearchResults,
  })
}

///|
fn Page::semantic_request_payload(
  self : Page,
  input : Input,
) -> @protocol.SearchSemanticPayload? {
  guard self.mode is Semantic else { return None }
  guard input.root is Some(root) && !self.query.is_empty() else { return None }
  Some({
    root: root.path,
    query: self.query,
    rules_dir: self.rules_dir,
    enable_builtin_rules: self.use_builtin_rules,
    session_key: "semantic-search:\{input.owner.channel.uri_authority()}:\{input.owner.session}:\{root.path}",
    generation: self.generation,
    max_results: MaxSearchResults,
  })
}

///|
test "checkout reset clears results while preserving the generation fence" {
  let input : Input = {
    owner: { channel: @interop.ChannelId::Local, session: "first" },
    root: Some(@common.Uri::parse("file:///work/a")),
  }
  let state = State::empty().handle(QueryChanged("moon"), input)
  let old_generation = state.page.generation
  let reset = state.reset_checkout()
  assert_eq(reset.page.query, "")
  assert_true(reset.page.matches.is_empty())
  assert_true(reset.page.phase is Idle)
  assert_true(reset.page.generation > old_generation)
}

///|
test "query changes debounce and stale replies cannot replace the page" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "one",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root) }
  let state = State::empty().handle(QueryChanged("moon"), input)
  let page = state.page
  assert_true(page.phase is Debouncing)
  assert_eq(page.delay_ms, 250)
  let stale : @protocol.SearchTextReply = {
    root: root.path,
    generation: page.generation - 1,
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let unchanged = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation - 1, reply=stale),
    input,
  )
  assert_true(unchanged == state)
}

///|
test "parking a checkout keeps its draft and fences the in-flight reply" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "suspend",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root) }
  let running = State::empty()
    .handle(QueryChanged("moon"), input)
    .handle(Submit, input)
  let page = running.page
  let old_generation = page.generation
  assert_true(page.phase is Loading)
  let suspended = running.park()
  let page = suspended.page
  assert_true(page.phase is Idle)
  assert_eq(page.query, "moon")
  assert_true(page.generation > old_generation)
  let stale : @protocol.SearchTextReply = {
    root: root.path,
    generation: old_generation,
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let after_stale = suspended.handle(
    Loaded(owner~, root=root.path, generation=old_generation, reply=stale),
    input,
  )
  assert_true(after_stale == suspended)
}

///|
test "refresh is immediate and loaded file groups can collapse and clear" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "one",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root) }
  let state = State::empty()
    .handle(QueryChanged("moon"), input)
    .handle(Refresh, input)
  let loading = state.page
  assert_true(loading.phase is Loading)
  assert_eq(loading.delay_ms, 0)
  let result : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 2,
    preview: "moon moon",
    preview_start_column: 1,
    ranges: [
      { start_column: 1, end_column: 5 },
      { start_column: 6, end_column: 10 },
    ],
  }
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    generation: loading.generation,
    matches: [result],
    match_count: 2,
    file_count: 1,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let ready = state.handle(
    Loaded(owner~, root=root.path, generation=loading.generation, reply~),
    input,
  )
  let page = ready.page
  assert_true(page.phase is Ready)
  assert_eq(page.match_count, 2)
  let collapsed = ready.handle(CollapseAll, input)
  let page = collapsed.page
  assert_true(page.collapsed.get("src/main.mbt").unwrap_or(false))
  let expanded = collapsed.handle(ToggleFile("src/main.mbt"), input)
  let page = expanded.page
  assert_false(page.collapsed.get("src/main.mbt").unwrap_or(false))
  let cleared = expanded.handle(ClearResults, input)
  let page = cleared.page
  assert_eq(page.query, "moon")
  assert_true(page.matches.is_empty())
  assert_true(page.phase is Idle)
}

///|
test "editor highlights include every retained match for the file" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "editor-highlights",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root) }
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
        line_number: 2,
        preview: "moon moon",
        preview_start_column: 1,
        ranges: [
          { start_column: 1, end_column: 5 },
          { start_column: 6, end_column: 10 },
        ],
      },
      {
        path: "src/main.mbt",
        line_number: 7,
        preview: "moon",
        preview_start_column: 1,
        ranges: [{ start_column: 1, end_column: 5 }],
      },
      {
        path: "src/other.mbt",
        line_number: 1,
        preview: "moon",
        preview_start_column: 1,
        ranges: [{ start_column: 1, end_column: 5 }],
      },
    ],
    match_count: 4,
    file_count: 2,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let ready = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation, reply~),
    input,
  )
  guard ready.editor_highlights("src/main.mbt") is Some(highlights) else {
    fail("main file should have editor highlights")
  }
  assert_eq(highlights.ranges(), [
    @common.Range(2, 1, 2, 5),
    @common.Range(2, 6, 2, 10),
    @common.Range(7, 1, 7, 5),
  ])
  assert_true(ready.editor_highlights("missing.mbt") is None)
  assert_true(
    ready
    .handle(QueryChanged("new query"), input)
    .editor_highlights("src/main.mbt")
    is None,
  )
}

///|
test "invalid regex replies retain their actionable Host error" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "regex",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root) }
  let state = State::empty()
    .handle(QueryChanged("("), input)
    .handle(ToggleRegex, input)
    .handle(Submit, input)
  let page = state.page
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    generation: page.generation,
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: Some({ code: "invalid_regex", message: "regex parse error" }),
  }
  let failed = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation, reply~),
    input,
  )
  guard failed.page.phase is Failed(code~, message~) else {
    fail("expected invalid regex phase")
  }
  assert_eq(code, "invalid_regex")
  assert_eq(message, "regex parse error")
}
