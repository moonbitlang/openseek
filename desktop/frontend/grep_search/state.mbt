///|
const SearchDebounceMs : Int = 250

///|
const MaxSearchResults : Int = 20000

///|
/// Retire every query/result derived from the outgoing checkout. Returning to
/// `Idle` drops the armed UUID, so an A -> B -> A transition cannot make an
/// old reply current again, while the armed Search mode and semantic settings
/// survive the switch.
pub fn State::reset_checkout(self : State) -> State {
  {
    ..State::empty(),
    mode: self.mode,
    semantic: { ..self.semantic, hits: [], partial: false, },
  }
}

///|
/// Arm the next request for the current inputs. Nothing to search for means
/// `Idle`, which by itself retires whatever was armed before.
fn State::schedule(self : State, input : Input, immediate~ : Bool) -> State {
  let has_query = match self.mode {
    Text => !self.text.query.is_empty()
    Semantic =>
      self.semantic.patterns.any(pattern => !pattern.trim().is_empty())
  }
  guard has_query && input.root is Some(_) else {
    return {
      ..self,
      text: { ..self.text, matches: [], },
      semantic: { ..self.semantic, hits: [], partial: false, },
      match_count: 0,
      file_count: 0,
      limit_hit: false,
      visible_lines: InitialVisibleSearchLines,
      phase: Idle,
    }
  }
  let request_id = @uuid.mint()
  {
    ..self,
    semantic: { ..self.semantic, hits: [], partial: false, },
    match_count: if self.mode is Semantic {
      0
    } else {
      self.match_count
    },
    file_count: if self.mode is Semantic {
      0
    } else {
      self.file_count
    },
    visible_lines: InitialVisibleSearchLines,
    // `immediate` skips the debounce, so the request is already the one in
    // flight; the subscription reads the wait from this arm.
    phase: if immediate {
      Loading(request_id~)
    } else {
      Debouncing(request_id~)
    },
  }
}

///|
/// Park host work because the current checkout disappeared. Ordinary UI
/// visibility changes intentionally do not call this: a search already issued
/// from the Explorer may settle while another inventory or tab is visible.
pub fn State::park(self : State) -> State {
  guard self.phase.request_id() is Some(_) else { return self }
  { ..self, phase: Idle, }
}

///|
pub fn State::handle(self : State, msg : Msg, input : Input) -> State {
  match msg {
    QueryChanged(query) =>
      { ..self, text: { ..self.text, query, }, }.schedule(
        input,
        immediate=false,
      )
    ModeChanged(mode) =>
      {
        ..self,
        mode,
        text: { ..self.text, matches: [], },
        semantic: { ..self.semantic, hits: [], partial: false, },
        match_count: 0,
        file_count: 0,
        collapsed: Map([]),
      }.schedule(input, immediate=false)
    ToggleCaseSensitive =>
      {
        ..self,
        text: { ..self.text, case_sensitive: !self.text.case_sensitive, },
      }.schedule(input, immediate=false)
    ToggleWholeWord =>
      { ..self, text: { ..self.text, whole_word: !self.text.whole_word, }, }.schedule(
        input,
        immediate=false,
      )
    ToggleRegex =>
      { ..self, text: { ..self.text, regex: !self.text.regex, }, }.schedule(
        input,
        immediate=false,
      )
    ToggleDetails => { ..self, details_open: !self.details_open, }
    IncludeChanged(include_glob) =>
      { ..self, include_glob, }.schedule(input, immediate=false)
    ExcludeChanged(exclude_glob) =>
      { ..self, exclude_glob, }.schedule(input, immediate=false)
    PatternChanged(index, value) => {
      let patterns = self.semantic.patterns.copy()
      if index < patterns.length() {
        patterns[index] = value
      }
      { ..self, semantic: { ..self.semantic, patterns, }, }.schedule(
        input,
        immediate=false,
      )
    }
    AddPattern =>
      {
        ..self,
        semantic: { ..self.semantic, patterns: self.semantic.patterns + [""], },
      }
    RemovePattern(index) => {
      let patterns = self.semantic.patterns.copy()
      if index < patterns.length() && patterns.length() > 1 {
        let _ = patterns.remove(index)
      }
      { ..self, semantic: { ..self.semantic, patterns, }, }.schedule(
        input,
        immediate=false,
      )
    }
    Submit | Refresh => self.schedule(input, immediate=true)
    ClearResults => { ..self.clear_results(), phase: Idle, }
    CollapseAll => {
      let collapsed : Map[String, Bool] = Map([])
      for path in self.active_paths() {
        collapsed[path] = true
      }
      { ..self, collapsed, }
    }
    ShowMore =>
      {
        ..self,
        visible_lines: (self.visible_lines + VisibleSearchLineStep).min(
          self.active_result_count(),
        ),
      }
    ToggleFile(path) => {
      let collapsed = self.collapsed.copy()
      if collapsed.get(path).unwrap_or(false) {
        collapsed.remove(path)
      } else {
        collapsed[path] = true
      }
      { ..self, collapsed, }
    }
    RequestStarted(request_id~) =>
      if self.phase is Debouncing(request_id=armed) && armed == request_id {
        { ..self, phase: Loading(request_id~), }
      } else {
        self
      }
    Loaded(reply~) => {
      // The armed UUID is the whole staleness fence: every root, mode, or
      // query change leaves the arm that holds it, so a match implies the
      // reply answers the current checkout's current query.
      guard self.phase.request_id() is Some(armed) &&
        armed == reply.request_id &&
        self.mode is Text else {
        return self
      }
      if reply.cancelled {
        return { ..self, phase: Idle, }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self.clear_results(),
        text: { ..self.text, matches: reply.matches, },
        match_count: reply.match_count,
        file_count: reply.file_count,
        limit_hit: reply.limit_hit,
        visible_lines: InitialVisibleSearchLines.min(reply.matches.length()),
        phase,
      }
    }
    SemanticLoaded(reply~) => {
      guard self.phase.request_id() is Some(armed) &&
        armed == reply.request_id &&
        self.mode is Semantic else {
        return self
      }
      if reply.cancelled {
        return {
          ..self,
          semantic: { ..self.semantic, hits: [], partial: false, },
          match_count: 0,
          file_count: 0,
          phase: Idle,
        }
      }
      let phase = match reply.error {
        None => Ready
        Some(error) => Failed(code=error.code, message=error.message)
      }
      {
        ..self,
        semantic: {
          ..self.semantic,
          hits: reply.matches,
          partial: reply.partial,
        },
        match_count: reply.match_count,
        file_count: reply.file_count,
        limit_hit: reply.limit_hit,
        visible_lines: InitialVisibleSearchLines.min(reply.matches.length()),
        phase,
      }
    }
    SemanticProgress(request_id~, matches~, match_count~, file_count~) => {
      // Partial rows are only meaningful for the search that is currently
      // in flight: once the final reply landed (Ready/Failed) or a newer
      // request started, late progress is stale and must not touch the
      // authoritative result set.
      guard self.phase is Loading(request_id=armed) &&
        armed == request_id &&
        self.mode is Semantic else {
        return self
      }
      {
        ..self,
        semantic: {
          ..self.semantic,
          hits: self.semantic.hits + matches,
          partial: true,
        },
        match_count,
        file_count,
      }
    }
    RequestFailed(request_id~, code~, message~) =>
      if self.phase.request_id() == Some(request_id) {
        {
          ..self,
          text: { ..self.text, matches: [], },
          semantic: { ..self.semantic, hits: [], partial: false, },
          match_count: 0,
          file_count: 0,
          limit_hit: false,
          visible_lines: InitialVisibleSearchLines,
          phase: Failed(code~, message~),
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
  guard self.phase is Ready else { return None }
  self.active_highlights(path)
}

///|
fn State::active_result_count(self : State) -> Int {
  match self.mode {
    Text => self.text.matches.length()
    Semantic => self.semantic.hits.length()
  }
}

///|
fn State::active_file_count(self : State) -> Int {
  let files : Map[String, Bool] = Map([])
  for path in self.active_paths() {
    files[path] = true
  }
  files.length()
}

///|
fn State::active_paths(self : State) -> Array[String] {
  match self.mode {
    Text => self.text.matches.map(result => result.path)
    Semantic => self.semantic.hits.map(hit => hit.path)
  }
}

///|
fn State::active_highlights(self : State, path : String) -> EditorHighlights? {
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
fn State::clear_results(self : State) -> State {
  {
    ..self,
    text: { ..self.text, matches: [], },
    semantic: { ..self.semantic, hits: [], partial: false, },
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    visible_lines: InitialVisibleSearchLines,
  }
}

///|
fn State::result_summary(self : State) -> SearchResultSummary {
  {
    match_count: self.match_count,
    file_count: self.file_count,
    limit_hit: self.limit_hit,
  }
}

///|
fn State::text_request_payload(
  self : State,
  input : Input,
  request_id~ : String,
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
    request_id,
    max_results: MaxSearchResults,
  })
}

///|
fn State::semantic_request_payload(
  self : State,
  input : Input,
  request_id~ : String,
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
    request_id,
    max_results: MaxSearchResults,
  })
}

///|
test "checkout reset clears results and disarms the request UUID fence" {
  let input : Input = {
    owner: { channel: @interop.ChannelId::Local, session: "first", },
    root: Some(@common.Uri::parse("file:///work/a")),
  }
  let state = State::empty().handle(QueryChanged("moon"), input)
  assert_true(state.pending_request_id() is Some(_))
  let reset = state.reset_checkout()
  assert_eq(reset.text.query, "")
  assert_true(reset.text.matches.is_empty())
  assert_true(reset.phase is Idle)
  assert_true(reset.pending_request_id() is None)
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
  assert_eq(switched_back.text.query, "text query")
  assert_eq(switched_back.semantic.patterns, ["inspect($(x:arg))", "match($x)"])
  assert_eq(switched_back.include_glob, "src/**")
  assert_eq(switched_back.exclude_glob, "generated/**")
  assert_false(switched_back.details_open)
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
  assert_true(state.phase is Debouncing(..))
  let stale : @protocol.SearchTextReply = {
    root: root.path,
    request_id: "stale-request",
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let unchanged = state.handle(Loaded(reply=stale), input)
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
  assert_true(state.phase is Loading(..))
  let request_id = state.pending_request_id().unwrap()
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
    SemanticProgress(request_id~, matches=[hit], match_count=1, file_count=1),
    input,
  )
  assert_eq(streamed.semantic.hits, [hit])
  assert_eq(streamed.match_count, 1)
  assert_eq(streamed.file_count, 1)
  // A progress frame for a previous request must not touch the page.
  let stale = state.handle(
    SemanticProgress(
      request_id="semantic-request-stale",
      matches=[hit],
      match_count=1,
      file_count=1,
    ),
    input,
  )
  assert_true(stale.semantic.hits.is_empty())
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
  let request_id = state.pending_request_id().unwrap()
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
  let first = state.handle(
    SemanticProgress(request_id~, matches=[hit], match_count=1, file_count=1),
    input,
  )
  let streamed = first.handle(
    SemanticProgress(request_id~, matches=[second], match_count=2, file_count=1),
    input,
  )
  assert_eq(streamed.semantic.hits, [hit, second])
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
  let request_id = state.pending_request_id().unwrap()
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
    SemanticProgress(request_id~, matches=[hit], match_count=1, file_count=1),
    input,
  )
  let next = streamed.handle(PatternChanged(0, "match($x)"), input)
  assert_true(next.semantic.hits.is_empty())
  assert_eq(next.match_count, 0)
  let cancelled = streamed.handle(
    SemanticLoaded(reply={
      root: root.path,
      request_id,
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
  assert_true(cancelled.semantic.hits.is_empty())
  assert_eq(cancelled.match_count, 0)
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
  let request_id = state.pending_request_id().unwrap()
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
    Loaded(reply={
      root: root.path,
      request_id,
      matches: [first, second],
      match_count: 2,
      file_count: 1,
      limit_hit: false,
      cancelled: false,
      error: None,
    }),
    input,
  )
  assert_eq(loaded.active_result_count(), 2)
  assert_eq(loaded.active_file_count(), 1)
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
  assert_true(running.phase is Loading(..))
  let old_request_id = running.pending_request_id().unwrap()
  let suspended = running.park()
  assert_true(suspended.phase is Idle)
  assert_eq(suspended.text.query, "moon")
  assert_true(suspended.pending_request_id() is None)
  let stale : @protocol.SearchTextReply = {
    root: root.path,
    request_id: old_request_id,
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let after_stale = suspended.handle(Loaded(reply=stale), input)
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
  assert_true(state.phase is Loading(..))
  let request_id = state.pending_request_id().unwrap()
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
    request_id,
    matches: [result],
    match_count: 2,
    file_count: 1,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let ready = state.handle(Loaded(reply~), input)
  assert_true(ready.phase is Ready)
  assert_eq(ready.match_count, 2)
  let collapsed = ready.handle(CollapseAll, input)
  assert_true(collapsed.collapsed.get("src/main.mbt").unwrap_or(false))
  let expanded = collapsed.handle(ToggleFile("src/main.mbt"), input)
  assert_false(expanded.collapsed.get("src/main.mbt").unwrap_or(false))
  let cleared = expanded.handle(ClearResults, input)
  assert_eq(cleared.text.query, "moon")
  assert_true(cleared.text.matches.is_empty())
  assert_true(cleared.phase is Idle)
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
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    request_id: state.pending_request_id().unwrap(),
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
  let ready = state.handle(Loaded(reply~), input)
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
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    request_id: state.pending_request_id().unwrap(),
    matches: [],
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    cancelled: false,
    error: Some({ code: "invalid_regex", message: "regex parse error", }),
  }
  let failed = state.handle(Loaded(reply~), input)
  guard failed.phase is Failed(code~, message~) else {
    fail("expected invalid regex phase")
  }
  assert_eq(code, "invalid_regex")
  assert_eq(message, "regex parse error")
}
