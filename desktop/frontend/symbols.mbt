// The composer's `#` symbol completion: search the active conversation's
// workspace symbols through the host's `workspace_symbols` op (served by
// `moon ide workspace-symbols`) and fold the matches into completion rows.
// Each reply carries the conversation owner and query it answers, so a reply
// that lost a device/session switch or was overtaken by a later keystroke is
// discarded.

///|
/// Search `query` against the conversation's workspace symbols and fold the
/// matches back as `SymbolsLoaded`.
fn read_workspace_symbols(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  query : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.lsp_workspace_symbols,
        {
          session: owner.session,
          query,
          workspace: workspace.map(value => value.0),
        },
      ) catch {
        _ => {
          scheduler.add(dispatch(SymbolsFailed(owner~, query~)))
          return
        }
      }
      scheduler.add(
        dispatch(
          SymbolsLoaded(owner~, query~, items=SymbolsProjection(reply).rows()),
        ),
      )
    })
  })
}

///|
/// Project a typed `workspace_symbols` reply into completion rows.
priv struct SymbolsProjection(@protocol.WorkspaceSymbolsReply)

///|
fn SymbolsProjection::rows(self : SymbolsProjection) -> Array[CompletionItem] {
  let rows : Array[CompletionItem] = []
  for item in self.0.symbols {
    guard !item.name.is_empty() else { continue }
    let range = @common.Range::Range(
      item.range.start.line + 1,
      item.range.start.col + 1,
      item.range.end.line + 1,
      item.range.end.col + 1,
    )
    rows.push(
      symbol_item(item.name, container=item.container, path=item.path, range~),
    )
  }
  rows
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
