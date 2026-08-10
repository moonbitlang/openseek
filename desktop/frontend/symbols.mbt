// Workspace-symbol transport shared by the composer's `#` completion and the
// unified Quick Open in either shell. The host op is served by
// `moon ide workspace-symbols`; this package projects its typed reply once,
// retaining kind and exact location until each UI maps it to its own row.

///|
/// One usable workspace symbol in viewer coordinates. `path` stays in the
/// host's root-relative form; `range` is one-based because the editor
/// open/reveal path consumes viewer coordinates rather than LSP wire values.
priv struct WorkspaceSymbol {
  name : String
  kind : Int?
  container : String?
  path : String
  range : @common.Range
} derive(Eq)

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
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.lsp_workspace_symbols,
        { root: root.path, query },
      ) catch {
        _ => {
          let message = match generation {
            Some(generation) =>
              QuickOpenSymbolsRequestFailed(owner~, query~, generation~)
            None => SymbolsFailed(owner~, query~)
          }
          scheduler.add(dispatch(message))
          return
        }
      }
      let items = SymbolsProjection(reply).symbols()
      let message = match generation {
        Some(generation) =>
          QuickOpenSymbolsLoaded(owner~, query~, generation~, items~)
        None => SymbolsLoaded(owner~, query~, items~)
      }
      scheduler.add(dispatch(message))
    })
  })
}

///|
/// Project a typed `workspace_symbols` reply into the shared UI form.
priv struct SymbolsProjection(@protocol.WorkspaceSymbolsReply)

///|
fn SymbolsProjection::symbols(
  self : SymbolsProjection,
) -> Array[WorkspaceSymbol] {
  let symbols : Array[WorkspaceSymbol] = []
  for item in self.0.symbols {
    guard !item.name.is_empty() else { continue }
    let range = @common.Range::Range(
      item.range.start.line + 1,
      item.range.start.col + 1,
      item.range.end.line + 1,
      item.range.end.col + 1,
    )
    symbols.push({
      name: item.name,
      kind: item.kind,
      container: item.container,
      path: item.path,
      range,
    })
  }
  symbols
}

///|
/// A compact secondary label shared by completion and quick-pick rows.
fn WorkspaceSymbol::detail(self : WorkspaceSymbol) -> String {
  let location = if self.path.is_empty() {
    ""
  } else {
    "\{self.path}:\{self.range.start_line_number}"
  }
  if self.container is Some(container) && !container.is_empty() {
    if location.is_empty() {
      container
    } else {
      "\{container} · \{location}"
    }
  } else {
    location
  }
}

///|
/// Map the shared symbol into the composer's row and insertion payload.
fn WorkspaceSymbol::completion_item(self : WorkspaceSymbol) -> CompletionItem {
  symbol_item(
    self.name,
    container=self.container,
    path=self.path,
    range=self.range,
  )
}

///|
/// Build a symbol's completion row. The label is the bare name; the detail
/// reads as `container · path:line` (each part dropped when blank). Accepting it
/// drops a reference into the composer for the agent — the name in backticks and
/// the location as the clickable `path:line` convention. `range` is one-based
/// (viewer coordinates); an empty range still anchors the reference's line,
/// it just gives the jump nothing to select.
fn symbol_item(
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
