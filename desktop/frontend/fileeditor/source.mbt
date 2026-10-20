///|
/// Credentials stay in the live context, never in document URIs or caches.
pub(all) struct CloudFiles {
  epoch : Int32
  token : String
} derive(Eq)

///|
pub extend CloudFiles with Eq::{equal, not_equal}

///|
fn Ctx::host_ready(self : Ctx) -> Bool {
  self.owner is @interop.Host(_) && self.checkout_ready()
}

///|
async fn read_source(
  owner : @interop.ConversationIdentity,
  cloud : CloudFiles?,
  path : @common.Uri,
  allow_large~ : Bool = false,
) -> Result[@protocol.ReadFileReply, String] {
  match owner {
    Host(owner) => {
      guard @resource.belongs_to(path, owner.channel) else {
        return Err("file root moved to another host before file read")
      }
      Ok(
        @interop.bridge_request(owner.channel, @commands.fs_read_file, {
          path: path.path,
          root: None,
        }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
    }
    Cloud(account~, session~) => {
      guard cloud is Some(cloud) &&
        @resource.cloud_root(@cloud.CloudOrigin, account, session) is Some(root) &&
        @resource.relative_to(path, root) is Some(relative) else {
        return Err("Cloud file no longer belongs to this conversation.")
      }
      @cloud.read_file(cloud.token, session, relative.0, allow_large~).map_err(failure => {
        failure.label()
      })
    }
  }
}

///|
/// Only the currently displayed Cloud size notice can authorize one read.
fn State::large_preview_file(self : State, ctx : Ctx) -> (@common.Uri, Doc)? {
  guard ctx.owner is @interop.Cloud(..) &&
    ctx.cloud_files is Some(_) &&
    ctx.panel_open &&
    self.owner == Some(ctx.owner) &&
    ctx.active_history_diff is None &&
    ctx.active_file is Some(path) &&
    self.docs.get(path)
    is Some({ state: TabOversized, review: None, stale: false, .. } as doc) else {
    return None
  }
  Some((path, doc))
}

///|
async fn read_directory_source(
  owner : @interop.ConversationIdentity,
  cloud : CloudFiles?,
  root : @common.Uri,
  path : @pathx.Relative,
) -> Result[@protocol.ReadDirReply, String] {
  match owner {
    Host(owner) => {
      guard @resource.belongs_to(root, owner.channel) else {
        return Err("file root moved to another host before directory read")
      }
      Ok(
        @interop.bridge_request(owner.channel, @commands.fs_read_directory, {
          path: @resource.join_relative(root, path).path,
        }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
    }
    Cloud(account~, session~) => {
      guard cloud is Some(cloud) &&
        @resource.cloud_root(@cloud.CloudOrigin, account, session) == Some(root) else {
        return Err("Cloud directory no longer belongs to this conversation.")
      }
      @cloud.read_directory(cloud.token, session, path.0).map_err(failure => {
        failure.label()
      })
    }
  }
}

///|
/// Cloud has no filesystem watcher. A manual Files refresh and a settled
/// generation share this invalidation, keeping background tabs lazy.
fn refresh_cloud_files(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard ctx.owner is @interop.Cloud(..) &&
    state.owner == Some(ctx.owner) &&
    ctx.root() is Some(root) else {
    return (@cmd.none, state)
  }
  let epoch = state.request_epoch + 1
  // This refresh advances the request epoch, retiring any earlier scan.
  // Restart an active index in the new epoch while retaining ready paths.
  let index = match state.index {
    IndexLoading(..) => IndexLoading(refresh_again=false)
    IndexReady(files~, truncated~, ..) =>
      IndexReady(files~, truncated~, refreshing=true, refresh_again=false)
    index => index
  }
  let directories = if ctx.panel_open {
    [@pathx.Relative::root(), ..state.expanded.filter(path => !path.is_root())]
  } else {
    []
  }
  let commands = directories.map(path => {
    read_directory(
      dispatch,
      ctx.owner,
      epoch,
      path,
      root=Some(root),
      cloud?=ctx.cloud_files,
    )
  })
  if index is (IndexLoading(..) | IndexReady(refreshing=true, ..)) {
    commands.push(
      list_files(
        dispatch,
        ctx.owner,
        epoch,
        root=Some(root),
        cloud?=ctx.cloud_files,
      ),
    )
  }
  let children = state.children.copy()
  for path in children.keys().to_array() {
    if !directories.contains(path) {
      children.remove(path)
    }
  }
  let docs = state.docs.map((_, doc) => { ..doc, stale: true, })
  if ctx.panel_open &&
    ctx.active_file is Some(path) &&
    docs.get(path) is Some(doc) {
    docs[path] = doc.prepare_read()
    commands.push(
      read_file(
        dispatch,
        ctx.owner,
        epoch,
        path,
        doc.name,
        range=None,
        cloud?=ctx.cloud_files,
      ),
    )
  }
  (
    @cmd.batch(commands),
    {
      ..state,
      request_epoch: epoch,
      index,
      docs,
      children,
      loading: directories,
      removed_directory_reads: Map([]),
      directory_errors: Map([]),
      error: None,
      explorer_mode: ExplorerFiles,
    },
  )
}
