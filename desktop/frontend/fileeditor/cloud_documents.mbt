///|
/// Park settled Cloud documents only. A loading tab is a bookmark whose next
/// activation starts a new read under the new owner's request epoch.
fn State::switch_documents(
  self : State,
  owner : @interop.ConversationIdentity,
  open_files : Array[@common.Uri],
) -> (
  Map[@common.Uri, Doc],
  Map[@interop.ConversationIdentity, Map[@common.Uri, Doc]],
) {
  let cached = self.cloud_documents.copy()
  if self.owner is Some(@interop.Cloud(..) as previous) {
    let settled = self.docs.filter((_, doc) => !(doc.state is TabLoading))
    if settled.is_empty() {
      cached.remove(previous)
    } else {
      cached[previous] = settled
    }
  }
  let parked = if owner is @interop.Cloud(..) {
    cached.get(owner)
  } else {
    None
  }
  let docs : Map[@common.Uri, Doc] = Map([])
  for path in open_files {
    docs[path] = parked
      .bind(docs => docs.get(path))
      .unwrap_or({
        name: @resource.label(path),
        state: TabLoading,
        review: None,
        stale: false,
      })
  }
  cached.remove(owner)
  (docs, cached)
}

///|
/// A background generation invalidates the parked documents without starting
/// reads. Activation uses the same default size limit as a manual refresh.
fn State::invalidate_cloud_documents(
  self : State,
  owner : @interop.ConversationIdentity,
) -> State {
  guard self.cloud_documents.get(owner) is Some(docs) else { return self }
  let cloud_documents = self.cloud_documents.copy()
  cloud_documents[owner] = docs.map((_, doc) => { ..doc, stale: true, })
  { ..self, cloud_documents, }
}

///|
/// Account retirement clears every parked strip; deletion clears one session.
/// Only document data and saved reading positions live beyond the active view.
pub fn forget_cloud_files(
  state : State,
  account : String,
  session? : String,
) -> (State, @cmd.Cmd) {
  let matches = fn(owner : @interop.ConversationIdentity) {
    owner is @interop.Cloud(account=current, session=id) &&
    current == account &&
    session.map_or(true, session => session == id)
  }
  let cloud_documents = state.cloud_documents.copy()
  let commands : Array[@cmd.Cmd] = []
  for owner in cloud_documents.keys().to_array() {
    if matches(owner) {
      cloud_documents.remove(owner)
      if @resource.cloud_root(@cloud.CloudOrigin, account, owner.session())
        is Some(root) {
        commands.push(forget_cloud_view_states(root))
      }
    }
  }
  let active = state.owner.map_or(false, matches)
  if active {
    commands.push(clear_document())
    if state.owner.bind(owner => {
        @resource.cloud_root(@cloud.CloudOrigin, account, owner.session())
      })
      is Some(root) {
      commands.push(forget_cloud_view_states(root))
    }
  }
  (
    {
      ..state,
      cloud_documents,
      docs: if active {
        Map([])
      } else {
        state.docs
      },
      request_epoch: if active {
        state.request_epoch + 1
      } else {
        state.request_epoch
      },
    },
    @cmd.batch(commands),
  )
}
