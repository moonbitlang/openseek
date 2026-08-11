// Unified Quick Open for the native desktop and browser console. This is
// Workbench chrome: it owns provider-prefix state, result navigation, and the
// handoff to the existing cross-file open/reveal path. `boot.mbt` owns global
// shortcut bindings; the embedded single-document Viewer remains unaware.

///|
const QuickOpenSymbolDebounceMs : Int = 150

///|
const QuickOpenFileDebounceMs : Int = 100

///|
const QuickOpenMaxFileResults : Int = 512

///|
const QuickOpenInputId : String = "quick-open-input"

///|
const QuickOpenListId : String = "quick-open-list"

///|
fn active_quick_open_owner(model : Model) -> @interop.ConversationKey {
  { channel: model.focused, session: model.active().session_id }
}

///|
fn quick_open_symbol_request(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> @cmd.Cmd {
  read_workspace_symbols(
    dispatch,
    owner,
    query,
    root=quick_open_root(model, owner),
    generation~,
  )
}

///|
priv enum QuickOpenFileRequestKind {
  PopulateFileCache
  QueryFileCache
}

///|
fn quick_open_file_request(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  root~ : @common.Uri?,
  cache_key : String,
  query : String,
  generation : Int,
  kind : QuickOpenFileRequestKind,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_search_files,
        {
          path: root.path,
          cache_key,
          query,
          max_results: match kind {
            PopulateFileCache => 0
            QueryFileCache => QuickOpenMaxFileResults
          },
          generation,
        },
      ) catch {
        _ => {
          scheduler.add(
            dispatch(
              match kind {
                PopulateFileCache =>
                  QuickOpenFileCacheRequestFailed(
                    owner~,
                    cache_key~,
                    generation~,
                  )
                QueryFileCache =>
                  QuickOpenFilesRequestFailed(
                    owner~,
                    cache_key~,
                    query~,
                    generation~,
                  )
              },
            ),
          )
          return
        }
      }
      if reply.cancelled {
        return
      }
      match kind {
        PopulateFileCache =>
          scheduler.add(
            dispatch(QuickOpenFileCacheLoaded(owner~, cache_key~, generation~)),
          )
        QueryFileCache => {
          let files = reply.files.filter_map(path => {
            if path.is_empty() {
              None
            } else {
              Some(@pathx.Relative(path))
            }
          })
          scheduler.add(
            dispatch(
              QuickOpenFilesLoaded(
                owner~,
                cache_key~,
                query~,
                generation~,
                files~,
                from_cache=reply.from_cache,
                limit_hit=reply.limit_hit,
              ),
            ),
          )
        }
      }
    })
  })
}

///|
fn cancel_quick_open_file_request(
  _dispatch : @cmd.Emit[Msg],
  model : Model,
  open : QuickOpen,
) -> @cmd.Cmd {
  guard open.mode() is QuickOpenFiles &&
    model.file_query_cache.active_key is Some(cache_key) else {
    return @cmd.none
  }
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          open.owner.channel,
          @commands.fs_cancel_search_files,
          { cache_key, generation: open.generation },
        ),
      ) catch {
        _ => ()
      }
    })
  })
}

///|
fn clear_quick_open_file_cache(
  owner : @interop.ConversationKey,
  cache_key : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          owner.channel,
          @commands.fs_clear_file_search_cache,
          { cache_key, },
        ),
      ) catch {
        _ => ()
      }
    })
  })
}

///|
fn QuickOpenMode::prefix(self : QuickOpenMode) -> String {
  match self {
    QuickOpenFiles => ""
    QuickOpenSymbols => "#"
  }
}

///|
fn QuickOpen::mode(self : QuickOpen) -> QuickOpenMode {
  if self.value.has_prefix("#") {
    QuickOpenSymbols
  } else {
    QuickOpenFiles
  }
}

///|
/// Provider-local query: file input verbatim, symbol input without exactly one
/// leading `#`.
fn QuickOpen::query(self : QuickOpen) -> String {
  match self.mode() {
    QuickOpenFiles => self.value
    QuickOpenSymbols => self.value[1:].to_owned()
  }
}

///|
/// Rewrite only the provider prefix, preserving the visible query suffix.
fn quick_open_value_for_mode(value : String, mode : QuickOpenMode) -> String {
  let suffix = if value.has_prefix("#") { value[1:].to_owned() } else { value }
  mode.prefix() + suffix
}

///|
/// Open tabs that still name usable files. Deleted tabs remain bookmarks in
/// the editor strip but must not become Quick Open results.
fn quick_open_open_files(model : Model) -> Array[@pathx.Relative] {
  let paths : Array[@pathx.Relative] = []
  for path in @dock.file_paths(model.dock) {
    match model.file_panel.docs.get(path) {
      Some(doc) if doc.state is @fileeditor.TabDeleted => ()
      _ => paths.push(path)
    }
  }
  paths
}

///|
/// Paths retained from the most recent Host result. They are only fast,
/// provisional candidates after the query changes; the debounced Host request
/// restores global top-K correctness.
fn quick_open_result_files(open : QuickOpen) -> Array[@pathx.Relative] {
  open.items.filter_map(item => {
    match item {
      QuickOpenFile(path) => Some(path)
      QuickOpenSymbol(_) => None
    }
  })
}

///|
fn quick_open_with_file_candidates(
  model : Model,
  open : QuickOpen,
  files : Array[@pathx.Relative],
  phase : QuickOpenPhase,
) -> QuickOpen {
  let candidates = quick_open_file_candidates(
    files,
    quick_open_open_files(model),
    @dock.active_file(model.dock),
  )
  {
    ..open,
    items: rank_file_quick_open_items(open.query(), candidates),
    selected: 0,
    phase,
  }
}

///|
fn quick_open_root(
  model : Model,
  owner : @interop.ConversationKey,
) -> @common.Uri? {
  guard model.find_conversation(owner.channel, owner.session) is Some(conv) else {
    return None
  }
  model.conversation_root(conv)
}

///|
fn file_query_cache_key(
  owner : @interop.ConversationKey,
  generation : Int,
) -> String {
  "quick-open:\{owner.session}:\{generation}"
}

///|
fn query_active_file_cache(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  open : QuickOpen,
) -> @cmd.Cmd {
  guard model.file_query_cache.active_key is Some(cache_key) else {
    return @cmd.none
  }
  quick_open_file_request(
    dispatch,
    open.owner,
    root=quick_open_root(model, open.owner),
    cache_key,
    open.query(),
    open.generation,
    QueryFileCache,
  )
}

///|
/// Create the cache state for one picker run. A compatible loaded key remains
/// active while a replacement warms. Re-entering the file provider inside the
/// same picker does not start another replacement; reopening the picker does.
fn ensure_file_query_cache(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  open : QuickOpen,
  replace_loaded : Bool,
  query_now : Bool,
) -> (@cmd.Cmd, Model) {
  let root = quick_open_root(model, open.owner)
  let previous = model.file_query_cache
  let compatible = previous.owner == Some(open.owner) && previous.root == root
  let cmds : Array[@cmd.Cmd] = []
  let mut cache = if compatible {
    previous
  } else {
    // Every Host cache key is created by a request with a concrete root. A
    // rootless entry only records that Quick Open opened too early, so there
    // is nothing to clear when Started later supplies that scratch root.
    if previous.root is Some(_) && previous.owner is Some(previous_owner) {
      if previous.active_key is Some(key) {
        cmds.push(clear_quick_open_file_cache(previous_owner, key))
      }
      if previous.loading_key is Some(key) && previous.active_key != Some(key) {
        cmds.push(clear_quick_open_file_cache(previous_owner, key))
      }
    }
    { owner: Some(open.owner), root, active_key: None, loading_key: None }
  }
  if cache.loading_key is None && (cache.active_key is None || replace_loaded) {
    let cache_key = file_query_cache_key(open.owner, open.generation)
    cache = { ..cache, loading_key: Some(cache_key) }
    cmds.push(
      quick_open_file_request(
        dispatch,
        open.owner,
        root~,
        cache_key,
        "",
        open.generation,
        PopulateFileCache,
      ),
    )
  }
  let next = { ..model, file_query_cache: cache }
  if query_now && cache.active_key is Some(_) {
    cmds.push(query_active_file_cache(dispatch, next, open))
  }
  (@cmd.batch(cmds), next)
}

///|
/// Restart the current provider when its conversation root changes, including
/// transitions to or from an unavailable root. The page-level update wrapper
/// calls this after every message, so Started, session restoration, and
/// worktree registry broadcasts share one transition. Advancing the generation
/// also fences replies that were already in flight against the previous root.
fn Model::restart_quick_open_after_root_change(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  previous : Model,
) -> (@cmd.Cmd, Model) {
  guard previous.quick_open is Some(previous_open) &&
    self.quick_open is Some(open) &&
    open.owner == previous_open.owner else {
    return (@cmd.none, self)
  }
  let previous_root = quick_open_root(previous, open.owner)
  let current_root = quick_open_root(self, open.owner)
  guard current_root != previous_root else { return (@cmd.none, self) }
  let generation = self.quick_open_generation + 1
  let restarted : QuickOpen = {
    ..open,
    items: [],
    selected: 0,
    phase: QuickOpenLoading,
    generation,
  }
  let next = {
    ..self,
    quick_open: Some(restarted),
    quick_open_generation: generation,
  }
  match restarted.mode() {
    QuickOpenFiles => {
      // Keep only currently open relative paths as provisional rows; Host
      // results from the previous root must disappear immediately.
      let projected = quick_open_with_file_candidates(
        next,
        restarted,
        [],
        QuickOpenLoading,
      )
      let next = { ..next, quick_open: Some(projected) }
      let (cache_cmd, next) = ensure_file_query_cache(
        dispatch, next, projected, true, true,
      )
      (
        @cmd.batch([
          cancel_quick_open_file_request(dispatch, self, open),
          cache_cmd,
        ]),
        next,
      )
    }
    QuickOpenSymbols =>
      (
        quick_open_symbol_request(
          dispatch,
          next,
          restarted.owner,
          restarted.query(),
          generation,
        ),
        next,
      )
  }
}

///|
/// Open a fresh palette for the focused conversation, or switch an existing
/// palette's provider while retaining its query suffix. Invoking the same
/// provider again only restores focus.
fn open_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  mode : QuickOpenMode,
) -> (@cmd.Cmd, Model) {
  guard model.project_picker is None &&
    model.archive_confirm is None &&
    !(model.update_ux is ConfirmingRestart(..)) &&
    !(model.bridge_state() is BridgeLost(_)) else {
    return (@cmd.none, model)
  }
  let owner = active_quick_open_owner(model)
  if model.quick_open is Some(current) && current.owner == owner {
    let value = quick_open_value_for_mode(current.value, mode)
    if value == current.value {
      return (focus_quick_open_after_render(), model)
    }
    return change_quick_open_value(dispatch, model, value)
  }
  let generation = model.quick_open_generation + 1
  let open : QuickOpen = {
    owner,
    value: mode.prefix(),
    items: [],
    selected: 0,
    phase: QuickOpenLoading,
    generation,
  }
  let next_base = {
    ..model,
    completion: None,
    launcher: { ..model.launcher, open: false },
    quick_open: Some(open),
    quick_open_generation: generation,
  }
  match mode {
    QuickOpenFiles => {
      let projected = quick_open_with_file_candidates(
        next_base,
        open,
        [],
        QuickOpenLoading,
      )
      let next = { ..next_base, quick_open: Some(projected) }
      let (cache_cmd, next) = ensure_file_query_cache(
        dispatch, next, projected, true, true,
      )
      (@cmd.batch([cache_cmd, focus_quick_open_after_render()]), next)
    }
    QuickOpenSymbols =>
      (
        @cmd.batch([
          quick_open_symbol_request(dispatch, next_base, owner, "", generation),
          focus_quick_open_after_render(),
        ]),
        next_base,
      )
  }
}

///|
/// Replace the visible input. File queries filter the latest bounded rows
/// immediately; both providers then arm a delayed request. Changing providers
/// also increments the generation so an old reply cannot land in another mode.
fn change_quick_open_value(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  value : String,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) else { return (@cmd.none, model) }
  if value == open.value {
    return (@cmd.none, model)
  }
  let cancel = cancel_quick_open_file_request(dispatch, model, open)
  let generation = model.quick_open_generation + 1
  let keeps_file_rows = open.mode() is QuickOpenFiles && !value.has_prefix("#")
  let next_open : QuickOpen = {
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
  let next_base = {
    ..model,
    quick_open: Some(next_open),
    quick_open_generation: generation,
  }
  match next_open.mode() {
    QuickOpenFiles => {
      let projected = quick_open_with_file_candidates(
        next_base,
        next_open,
        quick_open_result_files(next_open),
        QuickOpenDebouncing,
      )
      let next = { ..next_base, quick_open: Some(projected) }
      let (cache_cmd, next) = ensure_file_query_cache(
        dispatch, next, projected, false, false,
      )
      (
        @cmd.batch([
          cancel,
          cache_cmd,
          @cmd.delay(
            dispatch(
              QuickOpenFilesDue(
                owner=open.owner,
                query=next_open.query(),
                generation~,
              ),
            ),
            QuickOpenFileDebounceMs,
          ),
        ]),
        next,
      )
    }
    QuickOpenSymbols => {
      let query = next_open.query()
      let next = {
        ..next_base,
        quick_open: Some({ ..next_open, phase: QuickOpenDebouncing }),
      }
      (
        @cmd.batch([
          cancel,
          @cmd.delay(
            dispatch(QuickOpenDue(owner=open.owner, query~, generation~)),
            QuickOpenSymbolDebounceMs,
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
fn begin_quick_open_file_request(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenFiles &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is QuickOpenDebouncing else {
    return (@cmd.none, model)
  }
  let next = { ..model, quick_open: Some({ ..open, phase: QuickOpenLoading }) }
  (query_active_file_cache(dispatch, next, open), next)
}

///|
/// A successful background population atomically replaces the active cache.
/// The previous key is cleared only after this point, so a failed refresh can
/// never destroy the last usable picker cache.
fn apply_quick_open_file_cache_loaded(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationKey,
  cache_key : String,
  _generation : Int,
) -> (@cmd.Cmd, Model) {
  let cache = model.file_query_cache
  guard cache.owner == Some(owner) && cache.loading_key == Some(cache_key) else {
    return (@cmd.none, model)
  }
  let cmds : Array[@cmd.Cmd] = []
  if cache.active_key is Some(previous) && previous != cache_key {
    cmds.push(clear_quick_open_file_cache(owner, previous))
  }
  let next_cache = { ..cache, active_key: Some(cache_key), loading_key: None }
  let mut next = { ..model, file_query_cache: next_cache }
  // The first picker run has no old cache to query. Once population settles,
  // issue the current query. During a debounce, let the already-scheduled due
  // message retain VS Code's typing delay.
  if next.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenFiles &&
    !(open.phase is QuickOpenDebouncing) {
    next = { ..next, quick_open: Some({ ..open, phase: QuickOpenLoading }) }
    cmds.push(query_active_file_cache(dispatch, next, open))
  }
  (@cmd.batch(cmds), next)
}

///|
fn fail_quick_open_file_cache_load(
  model : Model,
  owner : @interop.ConversationKey,
  cache_key : String,
  _generation : Int,
) -> (@cmd.Cmd, Model) {
  let cache = model.file_query_cache
  guard cache.owner == Some(owner) && cache.loading_key == Some(cache_key) else {
    return (@cmd.none, model)
  }
  let next = { ..model, file_query_cache: { ..cache, loading_key: None } }
  let clear = clear_quick_open_file_cache(owner, cache_key)
  guard cache.active_key is None &&
    next.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenFiles else {
    return (clear, next)
  }
  (clear, { ..next, quick_open: Some({ ..open, phase: QuickOpenFailed }) })
}

///|
/// Adopt only the exact current query from the currently active cache key.
fn apply_quick_open_file_result(
  model : Model,
  owner : @interop.ConversationKey,
  cache_key : String,
  query : String,
  generation : Int,
  files : Array[@pathx.Relative],
  _from_cache : Bool,
  _limit_hit : Bool,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenFiles &&
    model.file_query_cache.active_key == Some(cache_key) &&
    open.query() == query &&
    open.generation == generation else {
    return (@cmd.none, model)
  }
  let ready = quick_open_with_file_candidates(
    model,
    open,
    files,
    QuickOpenReady,
  )
  (@cmd.none, { ..model, quick_open: Some(ready) })
}

///|
fn fail_quick_open_file_request(
  model : Model,
  owner : @interop.ConversationKey,
  cache_key : String,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenFiles &&
    model.file_query_cache.active_key == Some(cache_key) &&
    open.query() == query &&
    open.generation == generation else {
    return (@cmd.none, model)
  }
  (@cmd.none, { ..model, quick_open: Some({ ..open, phase: QuickOpenFailed }) })
}

///|
/// Start a delayed symbol request only when no later keystroke, close, reopen,
/// mode change, or conversation switch has overtaken it.
fn begin_quick_open_symbol_request(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenSymbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is QuickOpenDebouncing else {
    return (@cmd.none, model)
  }
  let next = { ..model, quick_open: Some({ ..open, phase: QuickOpenLoading }) }
  (quick_open_symbol_request(dispatch, next, owner, query, generation), next)
}

///|
/// Adopt only the exact outstanding symbol result. Symbols without a source
/// path remain available to composer mentions but are omitted here because
/// there is nowhere useful to navigate.
fn apply_quick_open_symbol_result(
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
  items : Array[WorkspaceSymbol],
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenSymbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is QuickOpenLoading else {
    return (@cmd.none, model)
  }
  let openable : Array[WorkspaceSymbol] = []
  for item in items {
    if !item.path.is_empty() {
      openable.push(item)
    }
  }
  (
    @cmd.none,
    {
      ..model,
      quick_open: Some({
        ..open,
        items: rank_symbol_quick_open_items(query, openable).map(item => {
          QuickOpenSymbol(item)
        }),
        selected: 0,
        phase: QuickOpenReady,
      }),
    },
  )
}

///|
fn fail_quick_open_symbol_request(
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) &&
    open.owner == owner &&
    open.mode() is QuickOpenSymbols &&
    open.query() == query &&
    open.generation == generation &&
    open.phase is QuickOpenLoading else {
    return (@cmd.none, model)
  }
  (
    @cmd.none,
    {
      ..model,
      quick_open: Some({
        ..open,
        items: [],
        selected: 0,
        phase: QuickOpenFailed,
      }),
    },
  )
}

///|
fn move_quick_open_selection(model : Model, delta : Int) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) else { return (@cmd.none, model) }
  let count = open.items.length()
  guard count > 0 else { return (@cmd.none, model) }
  let selected = (open.selected + delta + count) % count
  (
    scroll_quick_open_selection_after_render(selected),
    { ..model, quick_open: Some({ ..open, selected, }) },
  )
}

///|
fn select_quick_open_row(model : Model, index : Int) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) && open.items.get(index) is Some(_) else {
    return (@cmd.none, model)
  }
  (@cmd.none, { ..model, quick_open: Some({ ..open, selected: index }) })
}

///|
fn QuickOpen::current(self : QuickOpen) -> QuickOpenItem? {
  self.items.get(self.selected)
}

///|
fn open_quick_open_item(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  item : QuickOpenItem,
) -> (@cmd.Cmd, Model) {
  let cancel = match model.quick_open {
    Some(open) => cancel_quick_open_file_request(dispatch, model, open)
    None => @cmd.none
  }
  let prepared = { ..model, quick_open: None, screen: Chat }
  let (open_cmd, next) = match item {
    QuickOpenFile(path) => open_editor_at(dispatch, prepared, path.0, None)
    QuickOpenSymbol(symbol) =>
      open_editor_at(dispatch, prepared, symbol.path, Some(symbol.range))
  }
  (@cmd.batch([cancel, open_cmd]), next)
}

///|
fn dismiss_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) else { return (@cmd.none, model) }
  (
    cancel_quick_open_file_request(dispatch, model, open),
    { ..model, quick_open: None },
  )
}

///|
fn accept_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) && open.current() is Some(item) else {
    return (@cmd.none, model)
  }
  open_quick_open_item(dispatch, model, item)
}

///|
fn pick_quick_open_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  index : Int,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) && open.items.get(index) is Some(item) else {
    return (@cmd.none, model)
  }
  open_quick_open_item(dispatch, model, item)
}

///|
/// Conversation ownership is checked after every message, including pushes
/// that switch the focused device/session without coming from the palette.
fn close_stale_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open is Some(open) else { return (@cmd.none, model) }
  let owner = active_quick_open_owner(model)
  if owner == open.owner {
    (@cmd.none, model)
  } else {
    (
      cancel_quick_open_file_request(dispatch, model, open),
      { ..model, quick_open: None },
    )
  }
}

///|
fn focus_quick_open_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(QuickOpenInputId).to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn quick_open_row_id(index : Int) -> String {
  "quick-open-row-\{index}"
}

///|
fn scroll_quick_open_selection_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(quick_open_row_id(index)).to_option()
        is Some(row) {
        row.scroll_into_view_with_options(block="nearest", inline="nearest")
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Codicon class for the LSP SymbolKind numeric wire value. Related kinds are
/// intentionally grouped so the small quick-pick row has a stable visual
/// vocabulary rather than 26 barely distinguishable glyphs.
fn symbol_kind_icon_class(kind : Int?) -> String {
  match kind {
    Some(1) => "codicon-symbol-file"
    Some(2) | Some(3) | Some(4) | Some(19) => "codicon-symbol-namespace"
    Some(5) => "codicon-symbol-class"
    Some(6) | Some(9) | Some(12) | Some(24) => "codicon-symbol-method"
    Some(7) => "codicon-symbol-property"
    Some(8) => "codicon-symbol-field"
    Some(10) => "codicon-symbol-enum"
    Some(11) => "codicon-symbol-interface"
    Some(13)
    | Some(15)
    | Some(16)
    | Some(17)
    | Some(18)
    | Some(20)
    | Some(21) => "codicon-symbol-variable"
    Some(14) => "codicon-symbol-constant"
    Some(22) => "codicon-symbol-enum-member"
    Some(23) => "codicon-symbol-struct"
    Some(25) => "codicon-symbol-operator"
    Some(26) => "codicon-symbol-type-parameter"
    _ => "codicon-symbol-misc"
  }
}

///|
fn quick_open_key_attrs(dispatch : @cmd.Emit[Msg]) -> @html.Attrs {
  @html.Attrs::build().on_keydown(event => {
    if event.is_composing() {
      return @cmd.none
    }
    match event.key() {
      "ArrowDown" => {
        event.prevent_default()
        dispatch(QuickOpenMove(1))
      }
      "ArrowUp" => {
        event.prevent_default()
        dispatch(QuickOpenMove(-1))
      }
      "Enter" => {
        event.prevent_default()
        dispatch(QuickOpenAccept)
      }
      "Escape" => {
        event.prevent_default()
        dispatch(QuickOpenDismiss)
      }
      _ => @cmd.none
    }
  })
}

///|
fn QuickOpenItem::name(self : QuickOpenItem) -> String {
  match self {
    QuickOpenFile(path) => @fileeditor.basename(path)
    QuickOpenSymbol(symbol) => symbol.name
  }
}

///|
fn QuickOpenItem::detail(self : QuickOpenItem) -> String {
  match self {
    QuickOpenFile(path) => path.0
    QuickOpenSymbol(symbol) => symbol.detail()
  }
}

///|
fn QuickOpenItem::icon_class(self : QuickOpenItem) -> String {
  match self {
    QuickOpenFile(_) => "codicon-symbol-file"
    QuickOpenSymbol(symbol) => symbol_kind_icon_class(symbol.kind)
  }
}

///|
fn quick_open_empty_view(open : QuickOpen) -> @html.Html {
  let mode = open.mode()
  let (class, message) = match open.phase {
    QuickOpenDebouncing | QuickOpenLoading =>
      (
        "quick-open-empty",
        if mode is QuickOpenFiles {
          "Indexing files…"
        } else {
          "Searching symbols…"
        },
      )
    QuickOpenFailed =>
      (
        "quick-open-empty error",
        if mode is QuickOpenFiles {
          "File search failed"
        } else {
          "Symbol search failed"
        },
      )
    QuickOpenReady =>
      (
        "quick-open-empty",
        if mode is QuickOpenFiles {
          "No files found"
        } else {
          "No symbols found"
        },
      )
  }
  @html.div(
    class~,
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    message,
  )
}

///|
fn quick_open_view(dispatch : @cmd.Emit[Msg], open : QuickOpen) -> @html.Html {
  let mode = open.mode()
  let active_id = if open.current() is Some(_) {
    quick_open_row_id(open.selected)
  } else {
    ""
  }
  let dialog_label = if mode is QuickOpenFiles {
    "Search workspace files"
  } else {
    "Search workspace symbols"
  }
  let placeholder = if mode is QuickOpenFiles {
    "Search files"
  } else {
    "Search symbols"
  }
  let group_label = if mode is QuickOpenFiles { "Files" } else { "Symbols" }
  let base_input_attrs = quick_open_key_attrs(dispatch)
    .id(QuickOpenInputId)
    .role("combobox")
    .aria_label(dialog_label)
    .aria_controls(QuickOpenListId)
    .aria_expanded("true")
    .aria_autocomplete("list")
    .aria_keyshortcuts("Meta+P Control+P Meta+T Control+T")
  let input_attrs = if active_id.is_empty() {
    base_input_attrs
  } else {
    base_input_attrs.aria_activedescendant(active_id)
  }
  let rows : Array[@html.Html] = []
  for index, item in open.items {
    let selected = index == open.selected
    rows.push(
      @html.div(
        class=if selected {
          "quick-open-row selected"
        } else {
          "quick-open-row"
        },
        attrs=@html.Attrs::build()
          .id(quick_open_row_id(index))
          .role("option")
          .aria_selected(if selected { "true" } else { "false" })
          .on_mouseenter(_ => dispatch(QuickOpenSelect(index)))
          .on_mousedown(event => {
            event.prevent_default()
            dispatch(QuickOpenPick(index))
          }),
        [
          @html.span(
            class="quick-open-kind codicon \{item.icon_class()}",
            attrs=@html.Attrs::build().aria_hidden("true"),
            ([] : Array[@html.Html]),
          ),
          @html.div(class="quick-open-row-text", [
            @html.div(class="quick-open-name", item.name()),
            @html.div(class="quick-open-detail", item.detail()),
          ]),
        ],
      ),
    )
  }
  let list_children = if rows.is_empty() {
    [quick_open_empty_view(open)]
  } else {
    rows
  }
  let list_busy = match open.phase {
    QuickOpenDebouncing | QuickOpenLoading => "true"
    _ => "false"
  }
  @html.div(class="quick-open-backdrop", on_click=dispatch(QuickOpenDismiss), [
    @html.div(
      class="quick-open-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label(dialog_label)
        .on_click(event => {
          event.stop_propagation()
          @cmd.none
        }),
      [
        @html.div(class="quick-open-input-wrap", [
          icon(icon_search),
          @html.input(
            input_type=@html.InputType::Text,
            value=open.value,
            placeholder~,
            on_input=dispatch.map(value => QuickOpenValueChanged(value)),
            attrs=input_attrs,
          ),
        ]),
        @html.div(
          class="quick-open-group-label",
          attrs=@html.Attrs::build().id("quick-open-group-label"),
          group_label,
        ),
        @html.div(
          class="quick-open-list",
          attrs=@html.Attrs::build()
            .id(QuickOpenListId)
            .role("listbox")
            .aria_labelledby("quick-open-group-label")
            .aria_busy(list_busy),
          list_children,
        ),
      ],
    ),
  ])
}

// State-transition coverage for the quick pick. Commands are intentionally
// opaque here; tests assert that only the matching owner/query/generation can
// change the plain-data model and that accepting a row reaches the existing
// file-panel state.

///|
fn test_workspace_symbol(name : String, path : String) -> WorkspaceSymbol {
  {
    name,
    kind: Some(12),
    container: Some("Parser"),
    path,
    range: @common.Range::Range(5, 2, 5, 13),
  }
}

///|
test "Quick Open prefixes providers and works in both shells" {
  let dispatch = test_dispatch()
  let desktop = { ..test_model(), is_desktop: true }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), desktop)
  guard opened.quick_open is Some(first) else {
    fail("the shortcut should open the palette")
  }
  assert_eq(first.value, "")
  assert_true(first.mode() is QuickOpenFiles)
  assert_eq(first.items.length(), 0)
  let (_, changed) = update(dispatch, QuickOpenValueChanged("parse"), opened)
  guard changed.quick_open is Some(files) else {
    fail("typing should keep the palette open")
  }
  assert_eq(files.value, "parse")
  assert_true(files.mode() is QuickOpenFiles)
  let (_, symbols_model) = update(
    dispatch,
    QuickOpenOpen(QuickOpenSymbols),
    changed,
  )
  guard symbols_model.quick_open is Some(symbols) else {
    fail("switching providers should keep the palette open")
  }
  assert_eq(symbols.value, "#parse")
  assert_eq(symbols.query(), "parse")
  assert_true(symbols.phase is QuickOpenDebouncing)
  let generation = symbols.generation
  let (_, refocused) = update(
    dispatch,
    QuickOpenOpen(QuickOpenSymbols),
    symbols_model,
  )
  guard refocused.quick_open is Some(same) else { fail("palette expected") }
  assert_eq(same.value, "#parse")
  assert_eq(same.generation, generation)
  let (_, back_model) = update(
    dispatch,
    QuickOpenOpen(QuickOpenFiles),
    refocused,
  )
  guard back_model.quick_open is Some(back) else { fail("palette expected") }
  assert_eq(back.value, "parse")
  assert_true(back.mode() is QuickOpenFiles)
  let (_, fresh_symbols) = update(
    dispatch,
    QuickOpenOpen(QuickOpenSymbols),
    desktop,
  )
  guard fresh_symbols.quick_open is Some(fresh) else {
    fail("palette expected")
  }
  assert_eq(fresh.value, "#")
  assert_true(fresh.phase is QuickOpenLoading)
  let (_, browser) = update(dispatch, QuickOpenOpen(QuickOpenFiles), {
    ..desktop,
    is_desktop: false,
  })
  guard browser.quick_open is Some(browser_open) else {
    fail("the browser shortcut should open the palette")
  }
  assert_true(browser_open.mode() is QuickOpenFiles)
  assert_eq(browser_open.value, "")
}

///|
test "BridgeReady retries file and symbol Quick Open after a scratch root arrives" {
  let dispatch = test_dispatch()
  let base = {
    ..test_model().with_dev(dev => { ..dev, bridge: Connecting }),
    is_desktop: true,
  }
  let owner = active_quick_open_owner(base)
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), base)
  guard opened.quick_open is Some(waiting) &&
    opened.file_query_cache.loading_key is Some(cache_key) else {
    fail("rootless Quick Open should wait for its file cache")
  }
  assert_eq(opened.file_query_cache.root, None)
  let cwd = @interop.ChannelId::Local.test_resource("/work/scratch")
  let ready = BridgeReady(scratch_root=cwd)
  // The same message and model must produce the same plain-data state.
  let (_, first) = update_dev(dispatch, ready, opened)
  let (_, second) = update_dev(dispatch, ready, opened)
  assert_true(first.file_query_cache == second.file_query_cache)
  assert_true(first.quick_open == second.quick_open)
  assert_true(
    first.file_query_cache.root is Some(root) &&
    root.path == "/work/scratch/desktop-test",
  )
  guard first.file_query_cache.loading_key is Some(restarted_key) else {
    fail("BridgeReady should restart file-cache population")
  }
  assert_true(restarted_key != cache_key)
  guard first.quick_open is Some(retrying) else {
    fail("BridgeReady should leave the picker open")
  }
  assert_eq(retrying.generation, waiting.generation + 1)
  assert_true(retrying.phase is QuickOpenLoading)
  // A duplicate ready notification has no root change and must not restart.
  let (_, duplicate) = update_dev(dispatch, ready, first)
  assert_true(duplicate.file_query_cache == first.file_query_cache)
  assert_true(duplicate.quick_open == first.quick_open)
  let (_, symbol_opened) = update(
    dispatch,
    QuickOpenOpen(QuickOpenSymbols),
    base,
  )
  guard symbol_opened.quick_open is Some(symbol_waiting) else {
    fail("rootless symbol Quick Open should remain open")
  }
  let (_, symbol_first) = update_dev(dispatch, ready, symbol_opened)
  let (_, symbol_second) = update_dev(dispatch, ready, symbol_opened)
  assert_true(symbol_first.quick_open == symbol_second.quick_open)
  guard symbol_first.quick_open is Some(symbol_retrying) else {
    fail("BridgeReady should leave the symbol picker open")
  }
  assert_eq(symbol_retrying.generation, symbol_waiting.generation + 1)
  assert_eq(symbol_retrying.query(), symbol_waiting.query())
  assert_true(symbol_retrying.phase is QuickOpenLoading)
  let (_, stale) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner~,
      query=symbol_waiting.query(),
      generation=symbol_waiting.generation,
      items=[test_workspace_symbol("stale", "src/old.mbt")],
    ),
    symbol_first,
  )
  assert_true(stale.quick_open == symbol_first.quick_open)
  let (_, symbol_duplicate) = update_dev(dispatch, ready, symbol_first)
  assert_true(symbol_duplicate.quick_open == symbol_first.quick_open)
}

///|
test "file Quick Open populates a cache session before adopting ranked rows" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true }
  let owner = active_quick_open_owner(base)
  let docs : Map[@pathx.Relative, @fileeditor.Doc] = Map([])
  docs[Relative("src/open.mbt")] = {
    name: "open.mbt",
    state: @fileeditor.TabLoading,
    review: None,
    stale: false,
  }
  docs[Relative("src/deleted.mbt")] = {
    name: "deleted.mbt",
    state: @fileeditor.TabDeleted,
    review: None,
    stale: false,
  }
  docs[Relative("src/active.mbt")] = {
    name: "active.mbt",
    state: @fileeditor.TabLoading,
    review: None,
    stale: false,
  }
  let dock = base.dock
    |> @dock.open_file(Relative("src/open.mbt"))
    |> @dock.open_file(Relative("src/deleted.mbt"))
    |> @dock.open_file(Relative("src/active.mbt"))
  let seeded = {
    ..base,
    dock: { ..dock, owner: Some(owner) },
    file_panel: { ..base.file_panel, owner: Some(owner), docs },
  }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), seeded)
  guard opened.quick_open is Some(loading) else { fail("palette expected") }
  guard opened.file_query_cache.loading_key is Some(cache_key) else {
    fail("opening should populate a cache")
  }
  assert_true(opened.file_query_cache.active_key is None)
  assert_true(loading.phase is QuickOpenLoading)
  assert_eq(loading.items.map(item => item.detail()), [
    "src/active.mbt", "src/open.mbt",
  ])
  let (_, populated) = update(
    dispatch,
    QuickOpenFileCacheLoaded(owner~, cache_key~, generation=loading.generation),
    opened,
  )
  assert_eq(populated.file_query_cache.active_key, Some(cache_key))
  assert_true(populated.file_query_cache.loading_key is None)
  let (_, indexed) = update(
    dispatch,
    QuickOpenFilesLoaded(
      owner~,
      cache_key~,
      query="",
      generation=loading.generation,
      files=[
        Relative("src/open.mbt"),
        Relative("src/other.mbt"),
        Relative("src/active.mbt"),
      ],
      from_cache=true,
      limit_hit=false,
    ),
    populated,
  )
  guard indexed.quick_open is Some(ready) else { fail("palette expected") }
  assert_true(ready.phase is QuickOpenReady)
  assert_eq(ready.items.map(item => item.detail()), [
    "src/active.mbt", "src/open.mbt", "src/other.mbt",
  ])
  let (_, filtered) = update(dispatch, QuickOpenValueChanged("other"), indexed)
  guard filtered.quick_open is Some(filtered) else { fail("palette expected") }
  assert_eq(filtered.items.map(item => item.detail()), ["src/other.mbt"])
}

///|
test "an initial file cache failure is visible and retryable" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true }
  let owner = active_quick_open_owner(base)
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), base)
  guard opened.quick_open is Some(initial) else { fail("palette expected") }
  guard opened.file_query_cache.loading_key is Some(cache_key) else {
    fail("cache load expected")
  }
  let (_, failed) = update(
    dispatch,
    QuickOpenFileCacheRequestFailed(
      owner~,
      cache_key~,
      generation=initial.generation,
    ),
    opened,
  )
  guard failed.quick_open is Some(failure) else { fail("palette expected") }
  assert_true(failure.phase is QuickOpenFailed)
  assert_true(failed.file_query_cache.active_key is None)
  assert_true(failed.file_query_cache.loading_key is None)
  let (_, retrying) = update(dispatch, QuickOpenValueChanged("src"), failed)
  guard retrying.quick_open is Some(pending) else { fail("palette expected") }
  assert_true(pending.phase is QuickOpenDebouncing)
  assert_true(retrying.file_query_cache.loading_key is Some(_))
}

///|
test "reopening while cache population is running does not start another load" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), base)
  guard opened.file_query_cache.loading_key is Some(first_key) else {
    fail("cache load expected")
  }
  let (_, dismissed) = update(dispatch, QuickOpenDismiss, opened)
  assert_true(dismissed.quick_open is None)
  let (_, reopened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), dismissed)
  guard reopened.quick_open is Some(second) else { fail("palette expected") }
  assert_true(second.generation > 1)
  assert_eq(reopened.file_query_cache.loading_key, Some(first_key))
  assert_true(reopened.file_query_cache.active_key is None)
}

///|
test "file cache keeps the previous key until replacement succeeds" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true }
  let owner = active_quick_open_owner(base)
  let root = quick_open_root(base, owner)
  let seeded = {
    ..base,
    file_query_cache: {
      owner: Some(owner),
      root,
      active_key: Some("old-cache"),
      loading_key: None,
    },
  }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), seeded)
  guard opened.quick_open is Some(initial) else { fail("palette expected") }
  guard opened.file_query_cache.loading_key is Some(replacement) else {
    fail("a replacement cache should warm on each picker run")
  }
  assert_eq(opened.file_query_cache.active_key, Some("old-cache"))
  assert_true(initial.phase is QuickOpenLoading)
  let (_, cached) = update(
    dispatch,
    QuickOpenFilesLoaded(
      owner~,
      cache_key="old-cache",
      query="",
      generation=initial.generation,
      files=[Relative("src/main.mbt"), Relative("README.md")],
      from_cache=true,
      limit_hit=false,
    ),
    opened,
  )
  guard cached.quick_open is Some(ready) else { fail("palette expected") }
  assert_true(ready.phase is QuickOpenReady)
  assert_eq(ready.items.map(item => item.detail()), [
    "src/main.mbt", "README.md",
  ])
  let (_, refresh_failed) = update(
    dispatch,
    QuickOpenFileCacheRequestFailed(
      owner~,
      cache_key=replacement,
      generation=ready.generation,
    ),
    cached,
  )
  guard refresh_failed.quick_open is Some(still_ready) else {
    fail("palette expected")
  }
  assert_true(still_ready.phase is QuickOpenReady)
  assert_eq(still_ready.items.map(item => item.detail()), [
    "src/main.mbt", "README.md",
  ])
  assert_eq(refresh_failed.file_query_cache.active_key, Some("old-cache"))
  assert_true(refresh_failed.file_query_cache.loading_key is None)

  let (_, changed) = update(
    dispatch,
    QuickOpenValueChanged("src"),
    refresh_failed,
  )
  guard changed.quick_open is Some(debouncing) else { fail("palette expected") }
  assert_true(debouncing.phase is QuickOpenDebouncing)
  assert_eq(debouncing.items.map(item => item.detail()), ["src/main.mbt"])
  let (_, stale) = update(
    dispatch,
    QuickOpenFilesLoaded(
      owner~,
      cache_key="old-cache",
      query="",
      generation=ready.generation,
      files=[Relative("wrong.mbt")],
      from_cache=true,
      limit_hit=false,
    ),
    changed,
  )
  guard stale.quick_open is Some(still_debouncing) else {
    fail("palette expected")
  }
  assert_true(still_debouncing.phase is QuickOpenDebouncing)
  assert_eq(still_debouncing.items.map(item => item.detail()), ["src/main.mbt"])
  let (_, loading) = update(
    dispatch,
    QuickOpenFilesDue(owner~, query="src", generation=debouncing.generation),
    stale,
  )
  guard loading.quick_open is Some(in_flight) else { fail("palette expected") }
  assert_true(in_flight.phase is QuickOpenLoading)
  let (_, loaded) = update(
    dispatch,
    QuickOpenFilesLoaded(
      owner~,
      cache_key="old-cache",
      query="src",
      generation=in_flight.generation,
      files=[Relative("src/current.mbt")],
      from_cache=true,
      limit_hit=false,
    ),
    loading,
  )
  guard loaded.quick_open is Some(current) else { fail("palette expected") }
  assert_true(current.phase is QuickOpenReady)
  assert_eq(current.items.map(item => item.detail()), ["src/current.mbt"])
}

///|
test "leading hash switches providers and fences stale symbol replies" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenSymbols), {
    ..test_model(),
    is_desktop: true,
  })
  guard opened.quick_open is Some(initial) else { fail("palette expected") }
  let (_, changed) = update(dispatch, QuickOpenValueChanged("#parse"), opened)
  guard changed.quick_open is Some(pending) else { fail("palette expected") }
  let item = test_workspace_symbol("parse_hover", "src/main.mbt")
  let (_, stale) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner=initial.owner,
      query="",
      generation=initial.generation,
      items=[item],
    ),
    changed,
  )
  guard stale.quick_open is Some(still_pending) else {
    fail("a stale reply must not close the palette")
  }
  assert_true(still_pending.phase is QuickOpenDebouncing)
  assert_eq(still_pending.items.length(), 0)
  let (_, files) = update(dispatch, QuickOpenValueChanged("parse"), stale)
  guard files.quick_open is Some(files_open) else { fail("palette expected") }
  assert_true(files_open.mode() is QuickOpenFiles)
  let (_, still_files) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner=pending.owner,
      query=pending.query(),
      generation=pending.generation,
      items=[item],
    ),
    files,
  )
  guard still_files.quick_open is Some(current) else {
    fail("palette expected")
  }
  assert_true(current.mode() is QuickOpenFiles)
  assert_eq(current.items.length(), 0)
}

///|
test "symbol Quick Open distinguishes failure from an empty result" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenSymbols), {
    ..test_model(),
    is_desktop: true,
  })
  guard opened.quick_open is Some(_) else { fail("palette expected") }
  let (_, changed) = update(dispatch, QuickOpenValueChanged("#missing"), opened)
  guard changed.quick_open is Some(pending) else { fail("palette expected") }
  let (_, loading) = update(
    dispatch,
    QuickOpenDue(
      owner=pending.owner,
      query=pending.query(),
      generation=pending.generation,
    ),
    changed,
  )
  guard loading.quick_open is Some(in_flight) else { fail("palette expected") }
  assert_true(in_flight.phase is QuickOpenLoading)
  let (_, failed) = update(
    dispatch,
    QuickOpenSymbolsRequestFailed(
      owner=pending.owner,
      query=pending.query(),
      generation=pending.generation,
    ),
    loading,
  )
  guard failed.quick_open is Some(failure) else { fail("palette expected") }
  assert_true(failure.phase is QuickOpenFailed)
  assert_eq(failure.items.length(), 0)
  let (_, loaded) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner=pending.owner,
      query=pending.query(),
      generation=pending.generation,
      items=[],
    ),
    loading,
  )
  guard loaded.quick_open is Some(empty) else { fail("palette expected") }
  assert_true(empty.phase is QuickOpenReady)
  assert_eq(empty.items.length(), 0)
}

///|
test "Quick Open selection wraps and empty acceptance is a no-op" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenSymbols), {
    ..test_model(),
    is_desktop: true,
  })
  guard opened.quick_open is Some(search) else { fail("palette expected") }
  let (_, ready) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner=search.owner,
      query=search.query(),
      generation=search.generation,
      items=[
        test_workspace_symbol("alpha", "a.mbt"),
        test_workspace_symbol("beta", "b.mbt"),
        test_workspace_symbol("gamma", "c.mbt"),
      ],
    ),
    opened,
  )
  let (_, up) = update(dispatch, QuickOpenMove(-1), ready)
  guard up.quick_open is Some(last) else { fail("palette expected") }
  assert_eq(last.selected, 2)
  let (_, wrapped) = update(dispatch, QuickOpenMove(1), up)
  guard wrapped.quick_open is Some(first) else { fail("palette expected") }
  assert_eq(first.selected, 0)
  let (_, hovered) = update(dispatch, QuickOpenSelect(1), wrapped)
  guard hovered.quick_open is Some(second) else { fail("palette expected") }
  assert_eq(second.selected, 1)
  let (_, empty) = update(dispatch, QuickOpenValueChanged("#none"), hovered)
  let (_, unchanged) = update(dispatch, QuickOpenAccept, empty)
  assert_true(unchanged.quick_open == empty.quick_open)
}

///|
test "accepting files and symbols uses the shared editor open path" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true, screen: Settings }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), base)
  guard opened.quick_open is Some(files) else { fail("palette expected") }
  let file_ready = {
    ..opened,
    quick_open: Some({
      ..files,
      items: [QuickOpenFile(Relative("src/file.mbt"))],
      phase: QuickOpenReady,
    }),
  }
  let (_, file_accepted) = update(dispatch, QuickOpenAccept, file_ready)
  assert_true(file_accepted.quick_open is None)
  assert_true(file_accepted.screen is Chat)
  assert_true(
    @dock.active_file(file_accepted.dock) is Some(Relative("src/file.mbt")),
  )
  let (_, symbol_opened) = update(dispatch, QuickOpenOpen(QuickOpenSymbols), {
    ..file_accepted,
    screen: Settings,
  })
  guard symbol_opened.quick_open is Some(search) else {
    fail("palette expected")
  }
  let (_, ready) = update(
    dispatch,
    QuickOpenSymbolsLoaded(
      owner=search.owner,
      query=search.query(),
      generation=search.generation,
      items=[test_workspace_symbol("parse_hover", "src/main.mbt")],
    ),
    symbol_opened,
  )
  let (_, accepted) = update(dispatch, QuickOpenAccept, ready)
  assert_true(accepted.quick_open is None)
  assert_true(accepted.screen is Chat)
  assert_true(accepted.dock.open)
  assert_true(
    @dock.active_file(accepted.dock) is Some(Relative("src/main.mbt")),
  )
}

///|
test "switching conversations closes Quick Open" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    messages: [{ kind: User, content: "earlier", ts: None }],
  }
  let desktop = {
    ..test_model().replace_conversation(second),
    is_desktop: true,
  }
  let (_, opened) = update(dispatch, QuickOpenOpen(QuickOpenFiles), desktop)
  assert_true(opened.quick_open is Some(_))
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-second"),
    opened,
  )
  assert_eq(switched.active_session, "desktop-second")
  assert_true(switched.quick_open is None)
}
