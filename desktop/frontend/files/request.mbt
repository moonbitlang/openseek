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
/// Read a bounded snapshot from the same Host file-search service as Ctrl+P.
/// The cache key includes the conversation and concrete root, so moving from
/// a project checkout to a worktree cannot reuse the previous snapshot.
pub fn Request::run(
  self : Request,
  loaded : (Array[@pathx.Relative], Bool) -> @cmd.Cmd,
  failed : () -> @cmd.Cmd,
) -> @cmd.Cmd {
  guard self.root is Some(root) && @resource.belongs_to(root, self.channel) else {
    return failed()
  }
  let cache_key = "workspace-file-index:\{self.session}:\{root.path}"
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
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
    })
  })
}
