// A typed workspace-file request shared by conversation surfaces. The Host
// owns directory traversal and its search cache; this package owns the
// bounded reply's projection into workspace-relative paths.

///|
/// One Host response is deliberately bounded. Callers retain `truncated` so
/// they do not present the snapshot as a complete workspace inventory.
const MaxIndexedFiles : Int = 512

///|
/// One request bound to an authorized conversation and concrete root. Keeping
/// the fields private prevents callers from constructing an inconsistent
/// channel/root pair without passing through `Request`.
struct Request {
  channel : @interop.ChannelId
  session : String
  root : @common.Uri?
}

///|
pub fn Request::Request(
  channel : @interop.ChannelId,
  session : String,
  root : @common.Uri?,
) -> Request {
  { channel, session, root, }
}

///|
fn Request::cache_key(self : Request, root : @common.Uri) -> String {
  "workspace-file-index:\{self.session}:\{root.path}"
}

///|
/// Host cache keys are local to one connection, but ordered lanes are shared
/// by the whole page. Include the channel here so an unresolved remote scan
/// cannot delay an independent host that happens to use the same path/session.
fn Request::lane_key(self : Request, cache_key : String) -> String {
  "\{self.channel.uri_authority()}\u{0}file-search\u{0}\{cache_key}"
}

///|
/// Read a bounded snapshot from the same Host file-search service as Ctrl+P.
/// The cache key includes the conversation and concrete root, so moving from
/// a project checkout to a worktree cannot reuse the previous snapshot. Each
/// request clears that key first: this API represents a filesystem refresh,
/// not another query ranked against the Host's previous snapshot.
pub fn Request::run(
  self : Request,
  loaded : (Array[@pathx.Relative], Bool) -> @cmd.Cmd,
  failed : () -> @cmd.Cmd,
) -> @cmd.Cmd {
  guard self.root is Some(root) && @resource.belongs_to(root, self.channel) else {
    return failed()
  }
  let cache_key = self.cache_key(root)
  let lane_key = self.lane_key(cache_key)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Clear and repopulate one Host cache key as an indivisible sequence.
      // A conversation can return A→B→A while the first A scan is unresolved;
      // without this lane, its stale clear may overtake and cancel the current
      // A search even though the caller correctly rejects the stale reply.
      @interop.in_ordered_lane(lane_key, () => {
        ignore(
          @interop.bridge_request(
            self.channel,
            @commands.fs_clear_file_search_cache,
            { cache_key, },
          ),
        ) catch {
          _ => {
            scheduler.add(failed())
            return
          }
        }
        let reply = @interop.bridge_request(
          self.channel,
          @commands.fs_search_files,
          {
            path: root.path,
            cache_key,
            query: "",
            max_results: MaxIndexedFiles,
            generation: 0,
          },
        ) catch {
          _ => {
            scheduler.add(failed())
            return
          }
        }
        if reply.cancelled {
          scheduler.add(failed())
          return
        }
        let paths = [
          for path in reply.files if !path.is_empty() => @pathx.Relative(path)
        ]
        scheduler.add(loaded(paths, reply.limit_hit))
      }) catch {
        _ => scheduler.add(failed())
      }
    })
  })
}

///|
/// Interactive queries share the composer's 150 ms debounce pause. The timer
/// lives inside the subscription loader, so replacing the subscription key (a
/// new query or index epoch) is also the debounce cancellation.
const SearchingDebounceMs : Int = 150

///|
/// The extensible subscription payload. The runtime refreshes it in place on
/// every declaration pass, so the delivery commands stay current without
/// reloading the request.
priv suberror SearchingSub {
  Searching(
    Request,
    String,
    (Array[@pathx.Relative], Bool) -> @cmd.Cmd,
    () -> @cmd.Cmd
  )
}

///|
/// Declare one debounced interactive query against the complete Host snapshot
/// populated by `run`, as a subscription. The initial `run` reply may expose
/// only `MaxIndexedFiles` paths, but the Host cache retains the whole scan;
/// querying that cache keeps a truncated composer index from claiming that an
/// unlisted workspace file does not exist. `epoch` names the index snapshot
/// the caller is ranking against: a refreshed index changes the key, which
/// cancels the stale lookup and issues a fresh one. Dropping the declaration
/// cancels the pending debounce timer or mutes an in-flight reply.
pub fn Request::searching(
  self : Request,
  query : String,
  epoch~ : Int,
  loaded~ : (Array[@pathx.Relative], Bool) -> @cmd.Cmd,
  failed~ : () -> @cmd.Cmd,
) -> @sub.Sub {
  let root_key = if self.root is Some(root) {
    root.to_string()
  } else {
    "unrooted"
  }
  @sub.custom_sub(
    "workspace-file-query\u{0}\{self.channel.uri_authority()}\u{0}\{self.session}\u{0}\{root_key}\u{0}\{epoch}\u{0}\{query}",
    Local,
    SearchingSub::Searching(self, query, loaded, failed),
    @sub.SubLoader(searching_loader),
  )
}

///|
fn searching_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is SearchingSub::Searching(request, query, loaded, failed) else {
    return None
  }
  let mut loaded = loaded
  let mut failed = failed
  let mut active = true
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      guard request.root is Some(root) &&
        @resource.belongs_to(root, request.channel) else {
        scheduler.add(failed())
        return
      }
      let cache_key = request.cache_key(root)
      let lane_key = request.lane_key(cache_key)
      @js.async_run(() => {
        // Sharing the ordered lane with `run` refreshes prevents this query
        // from landing between their clear and repopulate steps. The Host's
        // cancellation frontier is never advanced for this cache key, so the
        // wire generation stays at the same constant `run` uses.
        @interop.in_ordered_lane(lane_key, () => {
          let reply = @interop.bridge_request(
            request.channel,
            @commands.fs_search_files,
            {
              path: root.path,
              cache_key,
              query,
              max_results: MaxIndexedFiles,
              generation: 0,
            },
          ) catch {
            _ => {
              if active {
                scheduler.add(failed())
              }
              return
            }
          }
          if reply.cancelled {
            return
          }
          let paths = [
            for path in reply.files if !path.is_empty() => @pathx.Relative(path)
          ]
          if active {
            scheduler.add(loaded(paths, reply.limit_hit))
          }
        }) catch {
          _ => if active { scheduler.add(failed()) }
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
      guard payload is SearchingSub::Searching(_, _, new_loaded, new_failed) else {
        return
      }
      loaded = new_loaded
      failed = new_failed
    },
  })
}

///|
/// Retire the Host snapshot after this conversation/root stops owning an
/// index. The same per-key lane orders the clear after any scan already in
/// flight, so an A→B→A transition cannot let the retired A scan repopulate its
/// cache after cleanup. Retirement is best-effort because the old connection
/// may already be gone; the frontend state has moved on either way.
pub fn Request::retire(self : Request) -> @cmd.Cmd {
  guard self.root is Some(root) && @resource.belongs_to(root, self.channel) else {
    return @cmd.none
  }
  let cache_key = self.cache_key(root)
  let lane_key = self.lane_key(cache_key)
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      @interop.in_ordered_lane(lane_key, () => {
        ignore(
          @interop.bridge_request(
            self.channel,
            @commands.fs_clear_file_search_cache,
            { cache_key, },
          ),
        ) catch {
          _ => ()
        }
      }) catch {
        _ => ()
      }
    })
  })
}
