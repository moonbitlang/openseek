// Typed workspace-symbol search shared by desktop conversation surfaces. The
// host supplies zero-based LSP coordinates; this package owns their one-time
// projection into the viewer coordinates every surface consumes.

///|
/// One usable workspace symbol in viewer coordinates. `path` stays in the
/// host's workspace-relative form and `range` is one-based for editor reveal.
pub(all) struct Symbol {
  name : String
  kind : Int?
  container : String?
  path : String
  range : @common.Range
} derive(Eq, Debug)

///|
/// Project a typed host reply into the shared UI form. Blank names are not
/// selectable and are therefore dropped at this boundary.
pub fn decode(reply : @protocol.WorkspaceSymbolsReply) -> Array[Symbol] {
  let symbols : Array[Symbol] = []
  for item in reply.symbols {
    guard !item.name.is_empty() else { continue }
    symbols.push({
      name: item.name,
      kind: item.kind,
      container: item.container,
      path: item.path,
      range: Range(
        item.range.start.line + 1,
        item.range.start.col + 1,
        item.range.end.line + 1,
        item.range.end.col + 1,
      ),
    })
  }
  symbols
}

///|
/// A compact secondary label shared by completion and quick-pick rows.
pub fn Symbol::detail(self : Symbol) -> String {
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
/// Search one host-authorized project or worktree root. `loaded` and `failed`
/// are source-owned commands, so each caller retains its own stale-reply fence
/// without duplicating transport or wire projection.
pub fn search(
  channel : @interop.ChannelId,
  query : String,
  root~ : @common.Uri,
  loaded~ : (Array[Symbol]) -> @cmd.Cmd,
  failed~ : @cmd.Cmd,
) -> @cmd.Cmd {
  guard @resource.belongs_to(root, channel) else { return @cmd.none }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.WorkspaceSymbolsReply = @interop.bridge_request(
        channel,
        @commands.lsp_workspace_symbols,
        { root: root.path, query },
      ) catch {
        _ => {
          scheduler.add(failed)
          return
        }
      }
      scheduler.add(loaded(decode(reply)))
    })
  })
}
