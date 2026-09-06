// Palette transitions and the Host requests they arm. Every entry point is
// total over the shell's `Input`: an owner or root that no longer matches the
// run that opened is reconciled here rather than in each caller.

///|
const SymbolDebounceMs : Int = 150

///|
const FileDebounceMs : Int = 100

///|
const MaxFileResults : Int = 512

///|
/// Open a fresh palette for the shell's focused conversation, or switch an
/// existing palette's provider while retaining its query suffix. Invoking the
/// same provider again only restores focus. The shell decides whether opening
/// is allowed at all — a competing modal or a lost bridge owns the screen.
pub fn State::open(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  provider : Provider,
) -> (@cmd.Cmd, State) {
  if self.open is Some(current) && current.owner == input.owner {
    let value = value_for_provider(current.value, provider)
    if value == current.value {
      return (focus_after_render(), self)
    }
    return self.change_value(emit, input, value)
  }
  let generation = self.generation + 1
  let open : Open = {
    owner: input.owner,
    root: input.root,
    value: provider.prefix(),
    items: [],
    selected: 0,
    phase: Loading,
    generation,
  }
  let started = { ..self, open: Some(open), generation, }
  match provider {
    Files => {
      let projected = with_file_candidates(input, open, [], Loading)
      let next = { ..started, open: Some(projected), }
      let (cache_cmd, next) = next.ensure_cache(
        emit, input, projected, true, true,
      )
      (@cmd.batch([cache_cmd, focus_after_render()]), next)
    }
    Symbols =>
      (
        @cmd.batch([
          symbol_request(emit, input.root, input.owner, "", generation),
          focus_after_render(),
        ]),
        started,
      )
  }
}

///|
/// Fold one palette message into the state. A `Some` third result is a row the
/// user accepted: the palette has already closed itself, and opening the target
/// is the shell's half of the same transition. `Pick` is the only message that
/// ever produces one.
pub fn State::handle(
  self : State,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  input : Input,
) -> (@cmd.Cmd, State, Accepted?) {
  match msg {
    ValueChanged(value) => {
      let (cmd, next) = self.change_value(emit, input, value)
      (cmd, next, None)
    }
    FilesDue(owner~, query~, generation~) => {
      let (cmd, next) = self.begin_file_request(
        emit, input, owner, query, generation,
      )
      (cmd, next, None)
    }
    FileCacheLoaded(owner~, cache_key~, generation~) => {
      let (cmd, next) = self.apply_cache_loaded(
        emit, input, owner, cache_key, generation,
      )
      (cmd, next, None)
    }
    FileCacheRequestFailed(owner~, cache_key~, generation~) => {
      let (cmd, next) = self.fail_cache_load(owner, cache_key, generation)
      (cmd, next, None)
    }
    // `from_cache` and `limit_hit` describe how the Host answered, not which
    // rows to show; the palette renders the same list either way.
    FilesLoaded(
      owner~,
      cache_key~,
      query~,
      generation~,
      files~,
      from_cache=_,
      limit_hit=_
    ) =>
      (
        @cmd.none,
        self.apply_file_result(
          input, owner, cache_key, query, generation, files,
        ),
        None,
      )
    FilesRequestFailed(owner~, cache_key~, query~, generation~) =>
      (
        @cmd.none,
        self.fail_file_request(owner, cache_key, query, generation),
        None,
      )
    SymbolsDue(owner~, query~, generation~) => {
      let (cmd, next) = self.begin_symbol_request(
        emit, input, owner, query, generation,
      )
      (cmd, next, None)
    }
    SymbolsLoaded(owner~, query~, generation~, items~) =>
      (
        @cmd.none,
        self.apply_symbol_result(owner, query, generation, items),
        None,
      )
    SymbolsRequestFailed(owner~, query~, generation~) =>
      (@cmd.none, self.fail_symbol_request(owner, query, generation), None)
    Move(delta) => {
      let (cmd, next) = self.move_selection(delta)
      (cmd, next, None)
    }
    Select(index) => (@cmd.none, self.select_row(index), None)
    Pick(index) => self.pick_row(index)
    Dismiss => {
      let (cmd, next) = self.close()
      (cmd, next, None)
    }
  }
}

///|
/// Fence the open palette against shell changes that produce no palette
/// message: a device/session switch, and a conversation whose concrete root
/// arrives or changes through connection metadata, restored session data, or a
/// worktree registry broadcast. The shell calls this once after every root
/// message so no handler has to remember either rule.
pub fn State::reconcile(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) else { return (@cmd.none, self) }
  // The run belongs to the conversation focused when it opened. A switch
  // retires it rather than repointing it at data the user did not ask for.
  guard open.owner == input.owner else {
    return (self.cancel_file_request(open), { ..self, open: None, })
  }
  guard open.root != input.root else { return (@cmd.none, self) }
  // Advancing the generation also fences replies already in flight against the
  // previous root.
  let generation = self.generation + 1
  let restarted : Open = {
    ..open,
    root: input.root,
    items: [],
    selected: 0,
    phase: Loading,
    generation,
  }
  let next = { ..self, open: Some(restarted), generation, }
  match restarted.provider() {
    Files => {
      // Keep only currently open relative paths as provisional rows; Host
      // results from the previous root must disappear immediately.
      let projected = with_file_candidates(input, restarted, [], Loading)
      let next = { ..next, open: Some(projected), }
      let (cache_cmd, next) = next.ensure_cache(
        emit, input, projected, true, true,
      )
      (@cmd.batch([self.cancel_file_request(open), cache_cmd]), next)
    }
    Symbols =>
      (
        symbol_request(
          emit,
          input.root,
          restarted.owner,
          restarted.query(),
          generation,
        ),
        next,
      )
  }
}

///|
/// Replace the visible input. File queries filter the latest bounded rows
/// immediately; both providers then arm a delayed request. Changing providers
/// also increments the generation so an old reply cannot land in another mode.
fn State::change_value(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  value : String,
) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) else { return (@cmd.none, self) }
  if value == open.value {
    return (@cmd.none, self)
  }
  let cancel = self.cancel_file_request(open)
  let generation = self.generation + 1
  let keeps_file_rows = open.provider() is Files && !value.has_prefix("#")
  let next_open : Open = {
    ..open,
    value,
    items: if keeps_file_rows {
      open.items
    } else {
      []
    },
    selected: 0,
    generation,
  }
  let started = { ..self, open: Some(next_open), generation, }
  match next_open.provider() {
    Files => {
      let projected = with_file_candidates(
        input,
        next_open,
        next_open.result_files(),
        Debouncing,
      )
      let next = { ..started, open: Some(projected), }
      let (cache_cmd, next) = next.ensure_cache(
        emit, input, projected, false, false,
      )
      (
        @cmd.batch([
          cancel,
          cache_cmd,
          @cmd.delay(
            emit(
              FilesDue(owner=open.owner, query=next_open.query(), generation~),
            ),
            FileDebounceMs,
          ),
        ]),
        next,
      )
    }
    Symbols => {
      let query = next_open.query()
      let next = { ..started, open: Some({ ..next_open, phase: Debouncing, }), }
      (
        @cmd.batch([
          cancel,
          @cmd.delay(
            emit(SymbolsDue(owner=open.owner, query~, generation~)),
            SymbolDebounceMs,
          ),
        ]),
        next,
      )
    }
  }
}

///|
/// Start a delayed Host file query only if no later keystroke, close, provider
/// switch, or conversation switch has overtaken it.
fn State::begin_file_request(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Files &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is Debouncing else {
    return (@cmd.none, self)
  }
  let next = { ..self, open: Some({ ..open, phase: Loading, }), }
  (next.query_active_cache(emit, input, open), next)
}

///|
/// A successful background population atomically replaces the active cache.
/// The previous key is cleared only after this point, so a failed refresh can
/// never destroy the last usable picker cache.
fn State::apply_cache_loaded(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  owner : @interop.ConversationKey,
  cache_key : String,
  _generation : Int,
) -> (@cmd.Cmd, State) {
  let cache = self.cache
  guard cache.owner == Some(owner) && cache.loading_key == Some(cache_key) else {
    return (@cmd.none, self)
  }
  let cmds : Array[@cmd.Cmd] = []
  if cache.active_key is Some(previous) && previous != cache_key {
    cmds.push(clear_file_cache(owner, previous))
  }
  let mut next = {
    ..self,
    cache: { ..cache, active_key: Some(cache_key), loading_key: None, },
  }
  // The first picker run has no old cache to query. Once population settles,
  // issue the current query. During a debounce, let the already-scheduled due
  // message retain VS Code's typing delay.
  if next.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Files &&
    !(open.phase is Debouncing) {
    next = { ..next, open: Some({ ..open, phase: Loading, }), }
    cmds.push(next.query_active_cache(emit, input, open))
  }
  (@cmd.batch(cmds), next)
}

///|
fn State::fail_cache_load(
  self : State,
  owner : @interop.ConversationKey,
  cache_key : String,
  _generation : Int,
) -> (@cmd.Cmd, State) {
  let cache = self.cache
  guard cache.owner == Some(owner) && cache.loading_key == Some(cache_key) else {
    return (@cmd.none, self)
  }
  let next = { ..self, cache: { ..cache, loading_key: None, }, }
  let clear = clear_file_cache(owner, cache_key)
  guard cache.active_key is None &&
    next.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Files else {
    return (clear, next)
  }
  (clear, { ..next, open: Some({ ..open, phase: Failed, }), })
}

///|
/// Adopt only the exact current query from the currently active cache key.
fn State::apply_file_result(
  self : State,
  input : Input,
  owner : @interop.ConversationKey,
  cache_key : String,
  query : String,
  generation : Int,
  files : Array[@pathx.Relative],
) -> State {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Files &&
    self.cache.active_key == Some(cache_key) &&
    open.query() == query &&
    open.generation == generation else {
    return self
  }
  { ..self, open: Some(with_file_candidates(input, open, files, Ready)), }
}

///|
fn State::fail_file_request(
  self : State,
  owner : @interop.ConversationKey,
  cache_key : String,
  query : String,
  generation : Int,
) -> State {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Files &&
    self.cache.active_key == Some(cache_key) &&
    open.query() == query &&
    open.generation == generation else {
    return self
  }
  { ..self, open: Some({ ..open, phase: Failed, }), }
}

///|
/// Start a delayed symbol request only when no later keystroke, close, reopen,
/// provider change, or conversation switch has overtaken it.
fn State::begin_symbol_request(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Symbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is Debouncing else {
    return (@cmd.none, self)
  }
  (
    symbol_request(emit, input.root, owner, query, generation),
    { ..self, open: Some({ ..open, phase: Loading, }), },
  )
}

///|
/// Adopt only the exact outstanding symbol result. Symbols without a source
/// path remain available to composer mentions but are omitted here because
/// there is nowhere useful to navigate.
fn State::apply_symbol_result(
  self : State,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
  items : Array[@symbols.Symbol],
) -> State {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Symbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is Loading else {
    return self
  }
  let openable = items.filter(item => !item.path.is_empty())
  {
    ..self,
    open: Some({
      ..open,
      items: rank_symbols(query, openable).map(item => SymbolRow(item)),
      selected: 0,
      phase: Ready,
    }),
  }
}

///|
fn State::fail_symbol_request(
  self : State,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> State {
  guard self.open is Some(open) &&
    open.owner == owner &&
    open.provider() is Symbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is Loading else {
    return self
  }
  { ..self, open: Some({ ..open, items: [], selected: 0, phase: Failed, }), }
}

///|
fn State::move_selection(self : State, delta : Int) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) else { return (@cmd.none, self) }
  let count = open.items.length()
  guard count > 0 else { return (@cmd.none, self) }
  let selected = (open.selected + delta + count) % count
  (
    scroll_selection_after_render(selected),
    { ..self, open: Some({ ..open, selected, }), },
  )
}

///|
fn State::select_row(self : State, index : Int) -> State {
  guard self.open is Some(open) && open.items.get(index) is Some(_) else {
    return self
  }
  { ..self, open: Some({ ..open, selected: index, }), }
}

///|
fn State::pick_row(self : State, index : Int) -> (@cmd.Cmd, State, Accepted?) {
  guard self.open is Some(open) && open.items.get(index) is Some(item) else {
    return (@cmd.none, self, None)
  }
  (
    self.cancel_file_request(open),
    { ..self, open: None, },
    Some(item.accepted()),
  )
}

///|
/// Retire the run, abandoning whatever it has in flight. The shell calls this
/// when it takes the screen for something else; the warm cache session is kept
/// so the next run does not pay for it again.
pub fn State::close(self : State) -> (@cmd.Cmd, State) {
  guard self.open is Some(open) else { return (@cmd.none, self) }
  (self.cancel_file_request(open), { ..self, open: None, })
}

///|
/// Rank the open editor tabs and the latest Host rows into visible rows.
fn with_file_candidates(
  input : Input,
  open : Open,
  files : Array[@pathx.Relative],
  phase : Phase,
) -> Open {
  let search = @files.Search(files, input.open_files, input.active_file)
  {
    ..open,
    items: search
    .rank(open.query(), limit=MaxFileResults)
    .map(file => FileRow(file)),
    selected: 0,
    phase,
  }
}

///|
/// Paths retained from the most recent Host result. They are only fast,
/// provisional candidates after the query changes; the debounced Host request
/// restores global top-K correctness.
fn Open::result_files(self : Open) -> Array[@pathx.Relative] {
  [
    for item in self.items if item is FileRow(file) => file.path
  ]
}

///|
fn file_cache_key(owner : @interop.ConversationKey, generation : Int) -> String {
  "quick-open:\{owner.session}:\{generation}"
}

///|
/// Create the cache state for one picker run. A compatible loaded key remains
/// active while a replacement warms. Re-entering the file provider inside the
/// same picker does not start another replacement; reopening the picker does.
fn State::ensure_cache(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  open : Open,
  replace_loaded : Bool,
  query_now : Bool,
) -> (@cmd.Cmd, State) {
  let previous = self.cache
  let compatible = previous.owner == Some(open.owner) &&
    previous.root == input.root
  let cmds : Array[@cmd.Cmd] = []
  let mut cache = if compatible {
    previous
  } else {
    // Every Host cache key is created by a request with a concrete root. A
    // rootless entry only records that Quick Open opened before placement was
    // available, so there is no Host cache to clear when a root later arrives.
    if previous.root is Some(_) && previous.owner is Some(previous_owner) {
      if previous.active_key is Some(key) {
        cmds.push(clear_file_cache(previous_owner, key))
      }
      if previous.loading_key is Some(key) && previous.active_key != Some(key) {
        cmds.push(clear_file_cache(previous_owner, key))
      }
    }
    {
      owner: Some(open.owner),
      root: input.root,
      active_key: None,
      loading_key: None,
    }
  }
  if cache.loading_key is None && (cache.active_key is None || replace_loaded) {
    let cache_key = file_cache_key(open.owner, open.generation)
    cache = { ..cache, loading_key: Some(cache_key), }
    cmds.push(
      file_request(
        emit,
        open.owner,
        root=input.root,
        cache_key,
        "",
        open.generation,
        PopulateCache,
      ),
    )
  }
  let next = { ..self, cache, }
  if query_now && cache.active_key is Some(_) {
    cmds.push(next.query_active_cache(emit, input, open))
  }
  (@cmd.batch(cmds), next)
}

///|
fn State::query_active_cache(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  open : Open,
) -> @cmd.Cmd {
  guard self.cache.active_key is Some(cache_key) else { return @cmd.none }
  file_request(
    emit,
    open.owner,
    root=input.root,
    cache_key,
    open.query(),
    open.generation,
    QueryCache,
  )
}

///|
fn State::cancel_file_request(self : State, open : Open) -> @cmd.Cmd {
  guard open.provider() is Files && self.cache.active_key is Some(cache_key) else {
    return @cmd.none
  }
  cancel_file_search(open.owner, cache_key, open.generation)
}
