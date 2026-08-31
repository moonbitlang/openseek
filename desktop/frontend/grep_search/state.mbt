///|
const SearchDebounceMs : Int = 250

///|
const MaxSearchResults : Int = 20000

///|
fn fresh_page() -> Page {
  {
    mode: Text,
    text: {
      query: "",
      regex: false,
      case_sensitive: false,
      whole_word: false,
      matches: [],
    },
    semantic: { patterns: [""], hits: [], partial: false, },
    details_open: false,
    include_glob: "",
    exclude_glob: "",
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    collapsed: Map([]),
    visible_lines: InitialVisibleSearchLines,
    phase: Idle,
    pattern_repair_phase: PatternRepairIdle,
    pattern_repair_message: None,
    pattern_repair_candidate: None,
    pattern_repair_validation_status: None,
    pattern_repair_instruction: "",
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
      text: fresh_page().text,
      semantic: { ..self.page.semantic, hits: [], partial: false, },
    },
    generation,
  }
}

///|
fn Input::root_text(self : Input) -> String {
  self.root.map(root => root.path).unwrap_or("")
}

///|
/// The session key a semantic request is issued under for this input. The
/// Host echoes it back in progress notifications so a stream can be fenced
/// against the same owner/root/generation triple as the final reply.
fn Input::semantic_session_key(self : Input) -> String {
  "semantic-search:\{self.owner.channel.uri_authority()}:\{self.owner.session}:\{self.root_text()}"
}

///|
fn State::schedule(
  self : State,
  page : Page,
  input : Input,
  immediate~ : Bool,
) -> State {
  let generation = self.generation + 1
  let has_query = match page.mode {
    Text => !page.text.query.is_empty()
    Semantic =>
      page.semantic.patterns.any(pattern => !pattern.trim().is_empty())
  }
  let page = if !has_query || input.root is None {
    {
      ..page,
      text: { ..page.text, matches: [], },
      semantic: { ..page.semantic, hits: [], partial: false, },
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
      text: page.text,
      semantic: { ..page.semantic, hits: [], partial: false, },
      match_count: if page.mode is Semantic {
        0
      } else {
        page.match_count
      },
      file_count: if page.mode is Semantic {
        0
      } else {
        page.file_count
      },
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
  { page, generation, }
}

///|
/// Park host work because the current checkout disappeared. Ordinary UI
/// visibility changes intentionally do not call this: a search already issued
/// from the Explorer may settle while another inventory or tab is visible.
pub fn State::park(self : State) -> State {
  let page = self.page
  guard page.phase is Debouncing || page.phase is Loading else { return self }
  let generation = self.generation + 1
  { generation, page: { ..page, phase: Idle, generation, }, }
}

///|
pub fn State::handle(self : State, msg : Msg, input : Input) -> State {
  let page = self.page
  match msg {
    QueryChanged(query) =>
      self.schedule(
        { ..page, text: { ..page.text, query, }, },
        input,
        immediate=false,
      )
    ModeChanged(mode) =>
      self.schedule(
        {
          ..page,
          mode,
          details_open: page.details_open,
          text: { ..page.text, matches: [], },
          semantic: { ..page.semantic, hits: [], partial: false, },
          pattern_repair_phase: PatternRepairIdle,
          pattern_repair_message: None,
          match_count: 0,
          file_count: 0,
          collapsed: Map([]),
        },
        input,
        immediate=false,
      )
    ToggleCaseSensitive =>
      self.schedule(
        {
          ..page,
          text: { ..page.text, case_sensitive: !page.text.case_sensitive, },
        },
        input,
        immediate=false,
      )
    ToggleWholeWord =>
      self.schedule(
        { ..page, text: { ..page.text, whole_word: !page.text.whole_word, }, },
        input,
        immediate=false,
      )
    ToggleRegex =>
      self.schedule(
        { ..page, text: { ..page.text, regex: !page.text.regex, }, },
        input,
        immediate=false,
      )
    ToggleDetails =>
      { ..self, page: { ..page, details_open: !page.details_open, }, }
    FixPattern =>
      {
        ..self,
        page: {
          ..page,
          pattern_repair_phase: PatternRepairComposer,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
        },
      }
    OpenPatternRepair(instruction) =>
      {
        ..self,
        page: {
          ..page,
          pattern_repair_phase: PatternRepairComposer,
          pattern_repair_instruction: instruction,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
        },
      }
    PatternRepairInstructionChanged(instruction) =>
      { ..self, page: { ..page, pattern_repair_instruction: instruction, }, }
    SubmitPatternRepair =>
      if page.pattern_repair_phase is PatternRepairComposer &&
        !page.pattern_repair_instruction.trim().to_owned().is_empty() {
        {
          ..self,
          page: {
            ..page,
            pattern_repair_phase: PatternRepairRequested,
            pattern_repair_message: None,
            pattern_repair_candidate: None,
          },
        }
      } else {
        self
      }
    PatternRepairPreview(
      root~,
      generation~,
      candidate_pattern~,
      validation_status~,
      message~
    ) =>
      if page.mode is Semantic &&
        input.root_text() == root &&
        page.generation == generation &&
        page.pattern_repair_phase is PatternRepairRequested {
        {
          ..self,
          page: {
            ..page,
            pattern_repair_phase: PatternRepairPreview,
            pattern_repair_message: Some(message),
            pattern_repair_candidate: Some(candidate_pattern),
            pattern_repair_validation_status: Some(validation_status),
          },
        }
      } else {
        self
      }
    AcceptPatternRepair =>
      match page.pattern_repair_candidate {
        Some(pattern) if page.mode is Semantic =>
          self.handle(PatternChanged(0, pattern), input)
        _ => self
      }
    RejectPatternRepair =>
      {
        ..self,
        page: {
          ..page,
          pattern_repair_phase: PatternRepairIdle,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
          pattern_repair_instruction: "",
        },
      }
    PatternRepairFailed(
      root~,
      generation~,
      candidate_pattern~,
      validation_status~,
      message~
    ) =>
      if page.mode is Semantic &&
        input.root_text() == root &&
        page.generation == generation &&
        page.pattern_repair_phase is PatternRepairRequested {
        {
          ..self,
          page: {
            ..page,
            pattern_repair_phase: PatternRepairFailed,
            pattern_repair_message: Some(message),
            pattern_repair_candidate: Some(candidate_pattern),
            pattern_repair_validation_status: Some(validation_status),
          },
        }
      } else {
        self
      }
    IncludeChanged(include_glob) =>
      self.schedule({ ..page, include_glob, }, input, immediate=false)
    ExcludeChanged(exclude_glob) =>
      self.schedule({ ..page, exclude_glob, }, input, immediate=false)
    PatternChanged(index, value) => {
      let patterns = page.semantic.patterns.copy()
      if index < patterns.length() {
        patterns[index] = value
      }
      self.schedule(
        {
          ..page,
          semantic: { ..page.semantic, patterns, },
          pattern_repair_phase: PatternRepairIdle,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
          pattern_repair_instruction: "",
        },
        input,
        immediate=false,
      )
    }
    AddPattern =>
      {
        ..self,
        page: {
          ..page,
          semantic: {
            ..page.semantic,
            patterns: page.semantic.patterns + [""],
          },
          pattern_repair_phase: PatternRepairIdle,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
        },
      }
    RemovePattern(index) => {
      let patterns = page.semantic.patterns.copy()
      if index < patterns.length() && patterns.length() > 1 {
        let _ = patterns.remove(index)
      }
      self.schedule(
        {
          ..page,
          semantic: { ..page.semantic, patterns, },
          pattern_repair_phase: PatternRepairIdle,
          pattern_repair_message: None,
          pattern_repair_candidate: None,
        },
        input,
        immediate=false,
      )
    }
    Submit | Refresh => self.schedule(page, input, immediate=true)
    ClearResults => {
      let generation = self.generation + 1
      {
        generation,
        page: { ..page.clear_results(), phase: Idle, generation, },
      }
    }
    CollapseAll => {
      let collapsed : Map[String, Bool] = Map([])
      for path in page.active_paths() {
        collapsed[path] = true
      }
      { ..self, page: { ..page, collapsed, }, }
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
      { ..self, page: { ..page, collapsed, }, }
    }
    RequestStarted(owner~, root~, generation~) =>
      if input.owner == owner &&
        input.root_text() == root &&
        page.generation == generation &&
        page.phase is Debouncing {
        { ..self, page: { ..page, phase: Loading, }, }
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
        return { ..self, page: { ..page, phase: Idle, }, }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self,
        page: {
          ..page.clear_results(),
          text: { ..page.text, matches: reply.matches, },
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
        return {
          ..self,
          page: {
            ..page,
            semantic: { ..page.semantic, hits: [], partial: false, },
            match_count: 0,
            file_count: 0,
            phase: Idle,
          },
        }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self,
        page: {
          ..page,
          semantic: {
            ..page.semantic,
            hits: reply.matches,
            partial: reply.partial,
          },
          match_count: reply.match_count,
          file_count: reply.file_count,
          limit_hit: reply.limit_hit,
          visible_lines: InitialVisibleSearchLines.min(reply.matches.length()),
          phase,
        },
      }
    }
    SemanticProgress(
      root~,
      session_key~,
      generation~,
      matches~,
      match_count~,
      file_count~
    ) => {
      // Partial rows are only meaningful for the search that is currently
      // in flight: once the final reply landed (Ready/Failed) or a newer
      // generation started, late progress is stale and must not touch the
      // authoritative result set.
      guard input.root_text() == root &&
        input.semantic_session_key() == session_key &&
        page.generation == generation &&
        page.mode is Semantic &&
        page.phase is Loading else {
        return self
      }
      {
        ..self,
        page: {
          ..page,
          semantic: {
            ..page.semantic,
            hits: page.semantic.hits + matches,
            partial: true,
          },
          match_count,
          file_count,
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
            text: { ..page.text, matches: [], },
            semantic: { ..page.semantic, hits: [], partial: false, },
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
  self.page.active_highlights(path)
}

///|
fn Page::active_result_count(self : Page) -> Int {
  match self.mode {
    Text => self.text.matches.length()
    Semantic => self.semantic.hits.length()
  }
}

///|
fn Page::active_file_count(self : Page) -> Int {
  let files : Map[String, Bool] = Map([])
  for path in self.active_paths() {
    files[path] = true
  }
  files.length()
}

///|
fn Page::active_paths(self : Page) -> Array[String] {
  match self.mode {
    Text => self.text.matches.map(result => result.path)
    Semantic => self.semantic.hits.map(hit => hit.path)
  }
}

///|
fn Page::active_highlights(self : Page, path : String) -> EditorHighlights? {
  let ranges : Array[@common.Range] = []
  match self.mode {
    Text =>
      for result in self.text.matches {
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
      for hit in self.semantic.hits {
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
fn Page::clear_results(self : Page) -> Page {
  {
    ..self,
    text: { ..self.text, matches: [], },
    semantic: { ..self.semantic, hits: [], partial: false, },
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    visible_lines: InitialVisibleSearchLines,
    pattern_repair_phase: PatternRepairIdle,
    pattern_repair_message: None,
    pattern_repair_candidate: None,
    pattern_repair_instruction: "",
  }
}

///|
fn Page::result_summary(self : Page) -> SearchResultSummary {
  {
    match_count: self.match_count,
    file_count: self.file_count,
    limit_hit: self.limit_hit,
  }
}

///|
fn Page::text_request_payload(
  self : Page,
  input : Input,
) -> @protocol.SearchTextPayload? {
  guard self.mode is Text else { return None }
  guard input.root is Some(root) && !self.text.query.is_empty() else {
    return None
  }
  Some({
    root: root.path,
    query: self.text.query,
    regex: self.text.regex,
    case_sensitive: self.text.case_sensitive,
    whole_word: self.text.whole_word,
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
  guard input.root is Some(root) else { return None }
  let patterns = self.semantic.patterns.filter(pattern => {
    !pattern.trim().is_empty()
  })
  guard !patterns.is_empty() else { return None }
  Some({
    root: root.path,
    patterns,
    include_glob: self.include_glob,
    exclude_glob: self.exclude_glob,
    session_key: input.semantic_session_key(),
    generation: self.generation,
    max_results: MaxSearchResults,
  })
}

///|
test "checkout reset clears results while preserving the generation fence" {
  let input : Input = {
    owner: { channel: @interop.ChannelId::Local, session: "first", },
    root: Some(@common.Uri::parse("file:///work/a")),
  }
  let state = State::empty().handle(QueryChanged("moon"), input)
  let old_generation = state.page.generation
  let reset = state.reset_checkout()
  assert_eq(reset.page.text.query, "")
  assert_true(reset.page.text.matches.is_empty())
  assert_true(reset.page.phase is Idle)
  assert_true(reset.page.generation > old_generation)
}

///|
test "mode changes preserve each search input and shared details" {
  let input : Input = {
    owner: { channel: @interop.ChannelId::Local, session: "mode-state", },
    root: Some(@common.Uri::parse("file:///work")),
  }
  let state = State::empty()
    .handle(QueryChanged("text query"), input)
    .handle(IncludeChanged("src/**"), input)
    .handle(ExcludeChanged("generated/**"), input)
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg))"), input)
    .handle(AddPattern, input)
    .handle(PatternChanged(1, "match($x)"), input)
  let switched_back = state.handle(ModeChanged(Text), input)
  assert_eq(switched_back.page.text.query, "text query")
  assert_eq(switched_back.page.semantic.patterns, [
    "inspect($(x:arg))", "match($x)",
  ])
  assert_eq(switched_back.page.include_glob, "src/**")
  assert_eq(switched_back.page.exclude_glob, "generated/**")
  assert_false(switched_back.page.details_open)
}

///|
test "query changes debounce and stale replies cannot replace the page" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "one",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
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
test "semantic progress streams partial hits and late progress is fenced" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "semantic-progress",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let state = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg))"), input)
    .handle(Submit, input)
  let page = state.page
  assert_true(page.phase is Loading)
  let session_key = "semantic-search:local:semantic-progress:/work"
  let hit : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "inspect",
    description: None,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 5,
    matched_source: "inspect(x)",
    source_context: [{ line: 1, text: "inspect(x)", is_match: true, }],
  }
  let streamed = state.handle(
    SemanticProgress(
      root=root.path,
      session_key~,
      generation=page.generation,
      matches=[hit],
      match_count=1,
      file_count=1,
    ),
    input,
  )
  assert_eq(streamed.page.semantic.hits, [hit])
  assert_eq(streamed.page.match_count, 1)
  assert_eq(streamed.page.file_count, 1)
  // A progress frame for a previous generation must not touch the page.
  let stale = state.handle(
    SemanticProgress(
      root=root.path,
      session_key~,
      generation=page.generation - 1,
      matches=[hit],
      match_count=1,
      file_count=1,
    ),
    input,
  )
  assert_true(stale.page.semantic.hits.is_empty())
}

///|
test "semantic progress batches append only new hits" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "semantic-batches",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let state = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg))"), input)
    .handle(Submit, input)
  let page = state.page
  let hit : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "inspect",
    description: None,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 5,
    matched_source: "inspect(x)",
    source_context: [{ line: 1, text: "inspect(x)", is_match: true, }],
  }
  let second = { ..hit, start_line: 2, end_line: 2, }
  let session_key = input.semantic_session_key()
  let first = state.handle(
    SemanticProgress(
      root=root.path,
      session_key~,
      generation=page.generation,
      matches=[hit],
      match_count=1,
      file_count=1,
    ),
    input,
  )
  let streamed = first.handle(
    SemanticProgress(
      root=root.path,
      session_key~,
      generation=page.generation,
      matches=[second],
      match_count=2,
      file_count=1,
    ),
    input,
  )
  assert_eq(streamed.page.semantic.hits, [hit, second])
}

///|
test "new semantic search clears partial results and cancellation clears them" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "semantic-clear",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let state = State::empty()
    .handle(ModeChanged(Semantic), input)
    .handle(PatternChanged(0, "inspect($(x:arg))"), input)
    .handle(Submit, input)
  let page = state.page
  let hit : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "inspect",
    description: None,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 5,
    matched_source: "inspect(x)",
    source_context: [{ line: 1, text: "inspect(x)", is_match: true, }],
  }
  let session_key = input.semantic_session_key()
  let streamed = state.handle(
    SemanticProgress(
      root=root.path,
      session_key~,
      generation=page.generation,
      matches=[hit],
      match_count=1,
      file_count=1,
    ),
    input,
  )
  let next = streamed.handle(PatternChanged(0, "match($x)"), input)
  assert_true(next.page.semantic.hits.is_empty())
  assert_eq(next.page.match_count, 0)
  let cancelled = next.handle(
    SemanticLoaded(owner~, root=root.path, generation=next.page.generation, reply={
      root: root.path,
      generation: next.page.generation,
      matches: [],
      match_count: 0,
      file_count: 0,
      limit_hit: false,
      cancelled: true,
      partial: false,
      error: None,
    }),
    input,
  )
  assert_true(cancelled.page.semantic.hits.is_empty())
  assert_eq(cancelled.page.match_count, 0)
}

///|
test "active result helpers share file grouping and highlight projection" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "active-results",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let state = State::empty().handle(QueryChanged("moon"), input)
  let page = state.page
  let first : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 2,
    preview: "moon moon",
    preview_start_column: 1,
    ranges: [
      { start_column: 1, end_column: 5, },
      { start_column: 6, end_column: 10, },
    ],
  }
  let second : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 4,
    preview: "moon",
    preview_start_column: 1,
    ranges: [{ start_column: 1, end_column: 5, }],
  }
  let loaded = state.handle(
    Loaded(owner~, root=root.path, generation=page.generation, reply={
      root: root.path,
      generation: page.generation,
      matches: [first, second],
      match_count: 2,
      file_count: 1,
      limit_hit: false,
      cancelled: false,
      error: None,
    }),
    input,
  )
  assert_eq(loaded.page.active_result_count(), 2)
  assert_eq(loaded.page.active_file_count(), 1)
  guard loaded.editor_highlights("src/main.mbt") is Some(highlights) else {
    fail("expected text highlights")
  }
  assert_eq(highlights.ranges(), [
    @common.Range(2, 1, 2, 5),
    @common.Range(2, 6, 2, 10),
    @common.Range(4, 1, 4, 5),
  ])
}

///|
test "parking a checkout keeps its draft and fences the in-flight reply" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "suspend",
  }
  let root = @common.Uri::parse("file:///work")
  let input : Input = { owner, root: Some(root), }
  let running = State::empty()
    .handle(QueryChanged("moon"), input)
    .handle(Submit, input)
  let page = running.page
  let old_generation = page.generation
  assert_true(page.phase is Loading)
  let suspended = running.park()
  let page = suspended.page
  assert_true(page.phase is Idle)
  assert_eq(page.text.query, "moon")
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
  let input : Input = { owner, root: Some(root), }
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
      { start_column: 1, end_column: 5, },
      { start_column: 6, end_column: 10, },
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
  assert_eq(page.text.query, "moon")
  assert_true(page.text.matches.is_empty())
  assert_true(page.phase is Idle)
}

///|
test "editor highlights include every retained match for the file" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "editor-highlights",
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
        line_number: 2,
        preview: "moon moon",
        preview_start_column: 1,
        ranges: [
          { start_column: 1, end_column: 5, },
          { start_column: 6, end_column: 10, },
        ],
      },
      {
        path: "src/main.mbt",
        line_number: 7,
        preview: "moon",
        preview_start_column: 1,
        ranges: [{ start_column: 1, end_column: 5, }],
      },
      {
        path: "src/other.mbt",
        line_number: 1,
        preview: "moon",
        preview_start_column: 1,
        ranges: [{ start_column: 1, end_column: 5, }],
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
  let input : Input = { owner, root: Some(root), }
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
    error: Some({ code: "invalid_regex", message: "regex parse error", }),
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
