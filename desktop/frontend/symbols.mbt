// Root-shell routing for the shared workspace-symbol package. OpenSeek keeps
// owner/generation identity in its own Msg; wire projection and transport live
// in `frontend/symbols`.

///|
type WorkspaceSymbol = @symbols.Symbol

///|
/// Search `query` against the conversation's workspace symbols. Without a
/// generation the reply belongs to the composer's `#` menu; a generation
/// routes it to Quick Open. Both retain owner/query identity so
/// update can discard an overtaken reply.
fn read_workspace_symbols(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  query : String,
  root~ : @common.Uri?,
  generation? : Int,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  let loaded = items => {
    dispatch(
      match generation {
        Some(generation) =>
          QuickOpenSymbolsLoaded(owner~, query~, generation~, items~)
        None => SymbolsLoaded(owner~, root~, query~, items~)
      },
    )
  }
  let failed = dispatch(
    match generation {
      Some(generation) =>
        QuickOpenSymbolsRequestFailed(owner~, query~, generation~)
      None => SymbolsFailed(owner~, root~, query~)
    },
  )
  @symbols.search(owner.channel, query, root~, loaded~, failed~)
}

///|
/// Map the shared symbol into the composer's row and insertion payload.
fn CompletionItem::from_symbol(symbol : WorkspaceSymbol) -> CompletionItem {
  CompletionItem::symbol(
    symbol.name,
    container=symbol.container,
    path=symbol.path,
    range=symbol.range,
  )
}

///|
/// Build a symbol's completion row. The label is the bare name; the detail
/// reads as `container · path:line` (each part dropped when blank). Accepting it
/// drops a reference into the composer for the agent — the name in backticks and
/// the location as the clickable `path:line` convention. `range` is one-based
/// (viewer coordinates); an empty range still anchors the reference's line,
/// it just gives the jump nothing to select.
fn CompletionItem::symbol(
  name : String,
  container~ : String?,
  path~ : String,
  range~ : @common.Range,
) -> CompletionItem {
  let location = if path.is_empty() {
    ""
  } else {
    "\{path}:\{range.start_line_number}"
  }
  let detail = if container is Some(container) && !container.is_empty() {
    if location.is_empty() {
      container
    } else {
      "\{container} · \{location}"
    }
  } else {
    location
  }
  let reference = if location.is_empty() {
    "`\{name}`"
  } else {
    "`\{name}` — \{location}"
  }
  let (target_path, target_range) = if path.is_empty() {
    (None, None)
  } else {
    (Some(path), Some(range))
  }
  {
    label: name,
    detail,
    command: "",
    insert: reference + " ",
    path: target_path,
    range: target_range,
  }
}
