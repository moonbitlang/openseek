// State-transition coverage for the quick pick. Commands are intentionally
// opaque here; these tests assert that only the matching query/request UUID
// can change the plain-data state, and that the Host cache session survives the
// failures it is designed to survive. What the palette *shows* is covered by
// the black-box tests against its rendered markup.

///|
fn test_emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn test_owner() -> @interop.ConversationKey {
  { channel: @interop.ChannelId::Local, session: "desktop-test", }
}

///|
fn test_uri(path : String) -> @common.Uri raise {
  guard @resource.of_path(@interop.ChannelId::Local, path) is Some(resource) else {
    fail("test resource path was invalid: \{path}")
  }
  resource
}

///|
fn test_input(
  root? : @common.Uri,
  owner? : @interop.ConversationKey,
  open_files? : Array[@pathx.Relative] = [],
  active_file? : @pathx.Relative,
) -> Input {
  { owner: owner.unwrap_or(test_owner()), root, open_files, active_file, }
}

///|
fn test_symbol(name : String, path : String) -> @symbols.Symbol {
  {
    name,
    kind: Some(12),
    container: Some("Parser"),
    path,
    range: @common.Range(5, 2, 5, 13),
  }
}

///|
/// Open the palette and keep only the state: these tests assert on plain data.
fn State::begin(self : State, input : Input, provider : Provider) -> State {
  let (_, next) = self.open(test_emit(), input, provider)
  next
}

///|
/// Apply one message and keep only the state.
fn State::step(self : State, msg : Msg, input : Input) -> State {
  let (_, next, _) = self.handle(test_emit(), msg, input)
  next
}

///|
fn State::settle(self : State, input : Input) -> State {
  let (_, next) = self.reconcile(test_emit(), input)
  next
}

///|
test "opening picks a provider and re-entering rewrites only its prefix" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Files)
  guard opened.open is Some(first) else {
    fail("the shortcut should open the palette")
  }
  assert_eq(first.value, "")
  assert_true(first.provider() is Files)
  assert_eq(first.items.length(), 0)
  let changed = opened.step(ValueChanged("parse"), input)
  guard changed.open is Some(files) else {
    fail("typing should keep the palette open")
  }
  assert_eq(files.value, "parse")
  assert_true(files.provider() is Files)
  let symbols_state = changed.begin(input, Symbols)
  guard symbols_state.open is Some(symbols) else {
    fail("switching providers should keep the palette open")
  }
  assert_eq(symbols.value, "#parse")
  assert_eq(symbols.query(), "parse")
  assert_true(symbols.phase is Debouncing)
  let request_id = symbols.request_id
  // Invoking the provider that is already selected only restores focus.
  let refocused = symbols_state.begin(input, Symbols)
  guard refocused.open is Some(same) else { fail("palette expected") }
  assert_eq(same.value, "#parse")
  assert_eq(same.request_id, request_id)
  let back = refocused.begin(input, Files)
  guard back.open is Some(back) else { fail("palette expected") }
  assert_eq(back.value, "parse")
  assert_true(back.provider() is Files)
  // A palette opened straight onto symbols starts querying immediately: there
  // is no keystroke to debounce.
  let fresh_symbols = State::empty().begin(input, Symbols)
  guard fresh_symbols.open is Some(fresh) else { fail("palette expected") }
  assert_eq(fresh.value, "#")
  assert_true(fresh.phase is Loading)
}

///|
test "a root that arrives after opening restarts both providers once" {
  let rootless = test_input()
  let waiting = State::empty().begin(rootless, Files)
  guard waiting.open is Some(pending) &&
    waiting.cache.loading_key is Some(cache_key) else {
    fail("rootless Quick Open should wait for its file cache")
  }
  assert_eq(waiting.cache.root, None)
  let placed = test_input(root=test_uri("/work/api"))
  // A second reconciliation against an unchanged root must not restart again.
  let first = waiting.settle(placed)
  assert_true(first.settle(placed) == first)
  assert_eq(first.cache.root, Some(test_uri("/work/api")))
  guard first.cache.loading_key is Some(restarted_key) else {
    fail("the arriving root should restart file-cache population")
  }
  assert_true(restarted_key != cache_key)
  guard first.open is Some(retrying) else {
    fail("the arriving root should leave the picker open")
  }
  assert_true(retrying.request_id != pending.request_id)
  assert_true(retrying.phase is Loading)
  let symbol_waiting = State::empty().begin(rootless, Symbols)
  guard symbol_waiting.open is Some(symbol_pending) else {
    fail("rootless symbol Quick Open should remain open")
  }
  let symbol_first = symbol_waiting.settle(placed)
  guard symbol_first.open is Some(symbol_retrying) else {
    fail("the arriving root should leave the symbol picker open")
  }
  assert_true(symbol_retrying.request_id != symbol_pending.request_id)
  assert_eq(symbol_retrying.query(), symbol_pending.query())
  assert_true(symbol_retrying.phase is Loading)
  // A reply minted against the previous root cannot settle the restarted run.
  let stale = symbol_first.step(
    SymbolsLoaded(
      query=symbol_pending.query(),
      request_id=symbol_pending.request_id,
      items=[test_symbol("stale", "src/old.mbt")],
    ),
    placed,
  )
  assert_true(stale == symbol_first)
}

///|
test "file Quick Open populates a cache session before adopting ranked rows" {
  let input = test_input(
    root=test_uri("/work/proj"),
    open_files=[Relative("src/open.mbt"), Relative("src/active.mbt")],
    active_file=Relative("src/active.mbt"),
  )
  let opened = State::empty().begin(input, Files)
  guard opened.open is Some(loading) else { fail("palette expected") }
  guard opened.cache.loading_key is Some(cache_key) else {
    fail("opening should populate a cache")
  }
  assert_true(opened.cache.active_key is None)
  assert_true(loading.phase is Loading)
  // Open tabs are immediately useful rows while the Host index warms.
  assert_eq(loading.items.map(item => item.detail()), [
    "src/active.mbt", "src/open.mbt",
  ])
  let populated = opened.step(FileCacheLoaded(cache_key~), input)
  assert_eq(populated.cache.active_key, Some(cache_key))
  assert_true(populated.cache.loading_key is None)
  let indexed = populated.step(
    FilesLoaded(
      cache_key~,
      query="",
      request_id=loading.request_id,
      files=[
        Relative("src/open.mbt"),
        Relative("src/other.mbt"),
        Relative("src/active.mbt"),
      ],
      from_cache=true,
      limit_hit=false,
    ),
    input,
  )
  guard indexed.open is Some(ready) else { fail("palette expected") }
  assert_true(ready.phase is Ready)
  assert_eq(ready.items.map(item => item.detail()), [
    "src/active.mbt", "src/open.mbt", "src/other.mbt",
  ])
  let filtered = indexed.step(ValueChanged("other"), input)
  guard filtered.open is Some(filtered) else { fail("palette expected") }
  assert_eq(filtered.items.map(item => item.detail()), ["src/other.mbt"])
}

///|
test "an initial file cache failure is visible and retryable" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Files)
  guard opened.open is Some(_) else { fail("palette expected") }
  guard opened.cache.loading_key is Some(cache_key) else {
    fail("cache load expected")
  }
  let failed = opened.step(FileCacheRequestFailed(cache_key~), input)
  guard failed.open is Some(failure) else { fail("palette expected") }
  assert_true(failure.phase is Failed)
  assert_true(failed.cache.active_key is None)
  assert_true(failed.cache.loading_key is None)
  let retrying = failed.step(ValueChanged("src"), input)
  guard retrying.open is Some(pending) else { fail("palette expected") }
  assert_true(pending.phase is Debouncing)
  assert_true(retrying.cache.loading_key is Some(_))
}

///|
test "reopening while cache population is running does not start another load" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Files)
  guard opened.cache.loading_key is Some(first_key) else {
    fail("cache load expected")
  }
  guard opened.open is Some(first) else { fail("palette expected") }
  let dismissed = opened.step(Dismiss, input)
  assert_false(dismissed.is_open())
  let reopened = dismissed.begin(input, Files)
  guard reopened.open is Some(second) else { fail("palette expected") }
  assert_true(second.request_id != first.request_id)
  assert_eq(reopened.cache.loading_key, Some(first_key))
  assert_true(reopened.cache.active_key is None)
}

///|
test "file cache keeps the previous key until replacement succeeds" {
  let input = test_input(root=test_uri("/work/proj"))
  let seeded = {
    ..State::empty(),
    cache: {
      owner: Some(test_owner()),
      root: Some(test_uri("/work/proj")),
      active_key: Some("old-cache"),
      loading_key: None,
    },
  }
  let opened = seeded.begin(input, Files)
  guard opened.open is Some(initial) else { fail("palette expected") }
  guard opened.cache.loading_key is Some(replacement) else {
    fail("a replacement cache should warm on each picker run")
  }
  assert_eq(opened.cache.active_key, Some("old-cache"))
  assert_true(initial.phase is Loading)
  let cached = opened.step(
    FilesLoaded(
      cache_key="old-cache",
      query="",
      request_id=initial.request_id,
      files=[Relative("src/main.mbt"), Relative("README.md")],
      from_cache=true,
      limit_hit=false,
    ),
    input,
  )
  guard cached.open is Some(ready) else { fail("palette expected") }
  assert_true(ready.phase is Ready)
  assert_eq(ready.items.map(item => item.detail()), [
    "src/main.mbt", "README.md",
  ])
  let refresh_failed = cached.step(
    FileCacheRequestFailed(cache_key=replacement),
    input,
  )
  guard refresh_failed.open is Some(still_ready) else {
    fail("palette expected")
  }
  assert_true(still_ready.phase is Ready)
  assert_eq(still_ready.items.map(item => item.detail()), [
    "src/main.mbt", "README.md",
  ])
  assert_eq(refresh_failed.cache.active_key, Some("old-cache"))
  assert_true(refresh_failed.cache.loading_key is None)
  let changed = refresh_failed.step(ValueChanged("src"), input)
  guard changed.open is Some(debouncing) else { fail("palette expected") }
  assert_true(debouncing.phase is Debouncing)
  assert_eq(debouncing.items.map(item => item.detail()), ["src/main.mbt"])
  let stale = changed.step(
    FilesLoaded(
      cache_key="old-cache",
      query="",
      request_id=ready.request_id,
      files=[Relative("wrong.mbt")],
      from_cache=true,
      limit_hit=false,
    ),
    input,
  )
  guard stale.open is Some(still_debouncing) else { fail("palette expected") }
  assert_true(still_debouncing.phase is Debouncing)
  assert_eq(still_debouncing.items.map(item => item.detail()), ["src/main.mbt"])
  let loading = stale.step(
    FilesDue(query="src", request_id=debouncing.request_id),
    input,
  )
  guard loading.open is Some(in_flight) else { fail("palette expected") }
  assert_true(in_flight.phase is Loading)
  let loaded = loading.step(
    FilesLoaded(
      cache_key="old-cache",
      query="src",
      request_id=in_flight.request_id,
      files=[Relative("src/current.mbt")],
      from_cache=true,
      limit_hit=false,
    ),
    input,
  )
  guard loaded.open is Some(current) else { fail("palette expected") }
  assert_true(current.phase is Ready)
  assert_eq(current.items.map(item => item.detail()), ["src/current.mbt"])
}

///|
test "leading hash switches providers and fences stale symbol replies" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Symbols)
  guard opened.open is Some(initial) else { fail("palette expected") }
  let changed = opened.step(ValueChanged("#parse"), input)
  guard changed.open is Some(pending) else { fail("palette expected") }
  let item = test_symbol("parse_hover", "src/main.mbt")
  let stale = changed.step(
    SymbolsLoaded(query="", request_id=initial.request_id, items=[item]),
    input,
  )
  guard stale.open is Some(still_pending) else {
    fail("a stale reply must not close the palette")
  }
  assert_true(still_pending.phase is Debouncing)
  assert_eq(still_pending.items.length(), 0)
  let files = stale.step(ValueChanged("parse"), input)
  guard files.open is Some(files_open) else { fail("palette expected") }
  assert_true(files_open.provider() is Files)
  let still_files = files.step(
    SymbolsLoaded(query=pending.query(), request_id=pending.request_id, items=[
      item,
    ]),
    input,
  )
  guard still_files.open is Some(current) else { fail("palette expected") }
  assert_true(current.provider() is Files)
  assert_eq(current.items.length(), 0)
}

///|
test "symbol Quick Open distinguishes failure from an empty result" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Symbols)
  let changed = opened.step(ValueChanged("#missing"), input)
  guard changed.open is Some(pending) else { fail("palette expected") }
  let loading = changed.step(
    SymbolsDue(query=pending.query(), request_id=pending.request_id),
    input,
  )
  guard loading.open is Some(in_flight) else { fail("palette expected") }
  assert_true(in_flight.phase is Loading)
  let failed = loading.step(
    SymbolsRequestFailed(query=pending.query(), request_id=pending.request_id),
    input,
  )
  guard failed.open is Some(failure) else { fail("palette expected") }
  assert_true(failure.phase is Failed)
  assert_eq(failure.items.length(), 0)
  let loaded = loading.step(
    SymbolsLoaded(query=pending.query(), request_id=pending.request_id, items=[]),
    input,
  )
  guard loaded.open is Some(empty) else { fail("palette expected") }
  assert_true(empty.phase is Ready)
  assert_eq(empty.items.length(), 0)
}

///|
test "symbols without a source path are dropped from the rows" {
  let input = test_input(root=test_uri("/work/proj"))
  let opened = State::empty().begin(input, Symbols)
  guard opened.open is Some(search) else { fail("palette expected") }
  let ready = opened.step(
    SymbolsLoaded(query=search.query(), request_id=search.request_id, items=[
      test_symbol("placed", "src/main.mbt"),
      test_symbol("unplaced", ""),
    ]),
    input,
  )
  guard ready.open is Some(rows) else { fail("palette expected") }
  assert_eq(rows.items.map(item => item.name()), ["placed"])
}
