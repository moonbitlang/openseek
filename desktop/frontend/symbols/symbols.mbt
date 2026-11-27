// Typed workspace-symbol search shared by desktop conversation surfaces. The
// host supplies zero-based LSP coordinates; this package owns their one-time
// projection into the viewer coordinates every surface consumes.

///|
/// One usable workspace symbol in viewer coordinates. `path` stays in the
/// host's workspace-relative form and `range` is one-based for editor reveal.
#derive(Eq, Debug)
pub(all) struct Symbol {
  name : String
  kind : Int32?
  container : String?
  path : String
  range : @common.Range
}

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
const SearchingDebounceMs : Int32 = 150

///|
/// The extensible subscription payload. The runtime refreshes it in place on
/// every declaration pass, so the delivery commands stay current without
/// reloading the request.
priv suberror SearchingSub {
  Searching(
    @interop.ConversationIdentity,
    String,
    @common.Uri,
    @cloud_client.Access?,
    (Array[Symbol]) -> @cmd.Cmd,
    @cmd.Cmd,
  )
}

///|
/// Declare one debounced workspace-symbol lookup as a subscription. While a
/// caller keeps this declared, exactly one request for (channel, root, query)
/// is wanted; dropping the declaration cancels the pending debounce timer or
/// mutes an in-flight reply. A reply therefore only ever reaches `loaded`
/// while its exact request identity is still declared.
pub fn searching(
  owner : @interop.ConversationIdentity,
  query : String,
  root~ : @common.Uri,
  cloud? : @cloud_client.Access,
  loaded~ : (Array[Symbol]) -> @cmd.Cmd,
  failed~ : @cmd.Cmd,
) -> @sub.Sub {
  @sub.custom_sub(
    "workspace-symbols\u{0}\{owner.key()}\u{0}\{cloud.map_or(0, access => access.epoch)}\u{0}\{root.to_string()}\u{0}\{query}",
    Local,
    SearchingSub::Searching(owner, query, root, cloud, loaded, failed),
    @sub.SubLoader(searching_loader),
  )
}

///|
fn searching_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload
    is SearchingSub::Searching(owner, query, root, cloud, loaded, failed) else {
    return None
  }
  let mut loaded = loaded
  let mut failed = failed
  let mut active = true
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      @js.Promise::from_async(() => {
        let reply = request_symbols(owner, root, cloud, query) catch {
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
      |> ignore
    },
    SearchingDebounceMs,
  )
  Some({
    unload: _ => {
      active = false
      @dom.window().clear_timeout(timer)
    },
    update_tagger: payload => {
      guard payload
        is SearchingSub::Searching(_, _, _, _, new_loaded, new_failed) else {
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
  owner : @interop.ConversationIdentity,
  query : String,
  root~ : @common.Uri,
  cloud? : @cloud_client.Access,
  loaded~ : (Array[Symbol]) -> @cmd.Cmd,
  failed~ : @cmd.Cmd,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = request_symbols(owner, root, cloud, query) catch {
        _ => {
          scheduler.add(failed)
          return
        }
      }
      scheduler.add(loaded(decode(reply)))
    })
    |> ignore
  })
}

///|
pub extend Symbol with Debug::{to_repr}

///|
pub extend Symbol with Eq::{equal, not_equal}

///|
async fn request_symbols(
  owner : @interop.ConversationIdentity,
  root : @common.Uri,
  cloud : @cloud_client.Access?,
  query : String,
) -> @protocol.WorkspaceSymbolsReply {
  match owner {
    Host(host) => {
      guard @resource.belongs_to(root, host.channel) else {
        fail("workspace owner changed")
      }
      @interop.bridge_request(host.channel, @commands.lsp_workspace_symbols, {
        session: host.session,
        root: root.path,
        query,
      })
    }
    Cloud(account~, session~) => {
      guard cloud is Some(access) &&
        @resource.cloud_root(@cloud_client.CloudOrigin, account, session) ==
        Some(root) else {
        fail("workspace owner changed")
      }
      let json = @cloud_client.request(
        @cloud_client.CloudOrigin,
        "/v1/sessions/\{@uri.encode_component(session)}/moonide/workspace-symbols",
        Post,
        token=access.token,
        body={ "query": Json(query) },
      )
      @json.from_json(json)
    }
  }
}
