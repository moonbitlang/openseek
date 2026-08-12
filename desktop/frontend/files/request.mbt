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
  { channel, session, root }
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
        let paths = reply.files.filter_map(path => {
          if path.is_empty() {
            None
          } else {
            Some(@pathx.Relative(path))
          }
        })
        scheduler.add(loaded(paths, reply.limit_hit))
      }) catch {
        _ => scheduler.add(failed())
      }
    })
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
