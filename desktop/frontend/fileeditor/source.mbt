///|
/// Credentials stay in the live context, never in document URIs or caches.
pub(all) struct CloudFiles {
  epoch : Int32
  token : String
} derive(Eq)

///|
pub extend CloudFiles with Eq::{equal, not_equal}

///|
/// Cloud document URIs use a virtual `/` root; model references use paths
/// relative to that session's workspace. Host references keep their path.
fn reference_file(
  owner : @interop.ConversationIdentity,
  path : @common.Uri,
) -> String {
  match owner {
    Host(_) => path.path
    Cloud(..) =>
      path.path.strip_prefix("/").unwrap_or(path.path.clamped_view()).to_owned()
  }
}

///|
fn Ctx::host_ready(self : Ctx) -> Bool {
  self.owner is @interop.Host(_) && self.checkout_ready()
}

///|
fn Doc::cloud_signature(
  self : Doc,
  owner : @interop.ConversationIdentity,
) -> String? {
  guard owner is @interop.Cloud(..) else { return None }
  match self.state {
    TabLoaded(sig~, ..)
    | TabOffice(sig~, ..)
    | TabPdf(sig~, ..)
    | TabImage(sig~, ..) => Some(sig)
    _ => None
  }
}

///|
fn State::surface_epoch(
  self : State,
  owner : @interop.ConversationIdentity,
) -> Int32 {
  match owner {
    Host(_) => self.request_epoch
    Cloud(..) => self.cloud_surface_epoch
  }
}

///|
fn State::accepts_surface_epoch(
  self : State,
  ctx : Ctx,
  owner : @interop.ConversationIdentity,
  epoch : Int32,
) -> Bool {
  self.surface_epoch(owner) == epoch &&
  (match owner {
    Host(_) => true
    Cloud(..) =>
      ctx.cloud_files is Some(files) && self.cloud_epoch == Some(files.epoch)
  })
}

///|
priv suberror SourceError {
  SourceError(String)
}

///|
async fn check_source(
  owner : @interop.ConversationIdentity,
  cloud : CloudFiles?,
  path : @common.Uri,
  sig : String,
) -> Bool {
  guard owner is @interop.Cloud(account~, session~) &&
    cloud is Some(cloud) &&
    @resource.cloud_root(@cloud.CloudOrigin, account, session) is Some(root) &&
    @resource.relative_to(path, root) is Some(relative) else {
    raise SourceError("Cloud file no longer belongs to this conversation.")
  }
  @cloud.file_unchanged(cloud.token, session, relative.0, sig) catch {
    @cloud.RequestError::RequestError(failure) =>
      raise SourceError(failure.label())
    _ => raise SourceError(@cloud.Failure::Unreachable.label())
  }
}

///|
async fn read_source(
  owner : @interop.ConversationIdentity,
  cloud : CloudFiles?,
  path : @common.Uri,
  allow_large~ : Bool = false,
) -> @protocol.ReadFileReply {
  match owner {
    Host(owner) => {
      guard @resource.belongs_to(path, owner.channel) else {
        raise SourceError("file root moved to another host before file read")
      }
      @interop.bridge_request(owner.channel, @commands.fs_read_file, {
        path: path.path,
        root: None,
      }) catch {
        error => raise SourceError(@interop.bridge_error_text(error))
      }
    }
    Cloud(account~, session~) => {
      guard cloud is Some(cloud) &&
        @resource.cloud_root(@cloud.CloudOrigin, account, session) is Some(root) &&
        @resource.relative_to(path, root) is Some(relative) else {
        raise SourceError("Cloud file no longer belongs to this conversation.")
      }
      @cloud.read_file(cloud.token, session, relative.0, allow_large~) catch {
        @cloud.RequestError::RequestError(failure) =>
          raise SourceError(failure.label())
        _ => raise SourceError(@cloud.Failure::Unreachable.label())
      }
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
) -> @protocol.ReadDirReply {
  match owner {
    Host(owner) => {
      guard @resource.belongs_to(root, owner.channel) else {
        raise SourceError(
          "file root moved to another host before directory read",
        )
      }
      @interop.bridge_request(owner.channel, @commands.fs_read_directory, {
        path: @resource.join_relative(root, path).path,
      }) catch {
        error => raise SourceError(@interop.bridge_error_text(error))
      }
    }
    Cloud(account~, session~) => {
      guard cloud is Some(cloud) &&
        @resource.cloud_root(@cloud.CloudOrigin, account, session) == Some(root) else {
        raise SourceError(
          "Cloud directory no longer belongs to this conversation.",
        )
      }
      @cloud.read_directory(cloud.token, session, path.0) catch {
        @cloud.RequestError::RequestError(failure) =>
          raise SourceError(failure.label())
        _ => raise SourceError(@cloud.Failure::Unreachable.label())
      }
    }
  }
}

///|
/// File events, manual refreshes and settled generations share invalidation,
/// keeping background tabs lazy.
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
        cached_sig?=doc.cloud_signature(ctx.owner),
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
    },
  )
}
