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
/// Composer symbol lookups share Quick Open's 150 ms debounce pause. The
/// timer lives inside the subscription loader, so replacing the subscription
/// key (a new query, root, or channel) is also the debounce cancellation.
const SearchingDebounceMs : Int = 150

///|
/// The extensible subscription payload. The runtime refreshes it in place on
/// every declaration pass, so the delivery commands stay current without
/// reloading the request.
priv suberror SearchingSub {
  Searching(
    @interop.ConversationKey,
    String,
    @common.Uri,
    (Array[Symbol]) -> @cmd.Cmd,
    @cmd.Cmd
  )
}

///|
/// Declare one debounced workspace-symbol lookup as a subscription. While a
/// caller keeps this declared, exactly one request for (channel, root, query)
/// is wanted; dropping the declaration cancels the pending debounce timer or
/// mutes an in-flight reply. A reply therefore only ever reaches `loaded`
/// while its exact request identity is still declared.
pub fn searching(
  owner : @interop.ConversationKey,
  query : String,
  root~ : @common.Uri,
  loaded~ : (Array[Symbol]) -> @cmd.Cmd,
  failed~ : @cmd.Cmd,
) -> @sub.Sub {
  @sub.custom_sub(
    "workspace-symbols\u{0}\{owner.channel.uri_authority()}\u{0}\{owner.session}\u{0}\{root.to_string()}\u{0}\{query}",
    Local,
    SearchingSub::Searching(owner, query, root, loaded, failed),
    @sub.SubLoader(searching_loader),
  )
}

///|
fn searching_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is SearchingSub::Searching(owner, query, root, loaded, failed) else {
    return None
  }
  let mut loaded = loaded
  let mut failed = failed
  let mut active = true
  let timer = @dom.window().set_timeout(
    () => {
      // An unauthorized root stays silently pending, matching `search`
      // returning no command: the caller's next declaration change resolves it.
      guard active && @resource.belongs_to(root, owner.channel) else { return }
      @js.async_run(() => {
        let reply : @protocol.WorkspaceSymbolsReply = @interop.bridge_request(
          owner.channel,
          @commands.lsp_workspace_symbols,
          { session: owner.session, root: root.path, query },
        ) catch {
          _ => {
            if active {
              scheduler.add(failed)
            }
            return
          }
        }
        if active {
          scheduler.add(loaded(decode(reply)))
        }
      })
    },
    SearchingDebounceMs,
  )
  Some({
    unload: _ => {
      active = false
      @dom.window().clear_timeout(timer)
    },
    update_tagger: payload => {
      guard payload is SearchingSub::Searching(_, _, _, new_loaded, new_failed) else {
        return
      }
      loaded = new_loaded
      failed = new_failed
    },
  })
}

///|
/// Search one host-authorized project or worktree root. `loaded` and `failed`
/// are source-owned commands, so each caller retains its own stale-reply fence
/// without duplicating transport or wire projection.
pub fn search(
  owner : @interop.ConversationKey,
  query : String,
  root~ : @common.Uri,
  loaded~ : (Array[Symbol]) -> @cmd.Cmd,
  failed~ : @cmd.Cmd,
) -> @cmd.Cmd {
  guard @resource.belongs_to(root, owner.channel) else { return @cmd.none }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.WorkspaceSymbolsReply = @interop.bridge_request(
        owner.channel,
        @commands.lsp_workspace_symbols,
        { session: owner.session, root: root.path, query },
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
