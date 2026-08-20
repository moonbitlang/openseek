// Which engine host a request is for. Every feature package passes a typed
// `Request` to `bridge_request`; the channel only chooses the transport. The
// request becomes a method name plus JSON at that transport's edge
// (docs/remote-protocol.md).

///|
/// One engine host the page can talk to. `Local` is the page's own host —
/// the injected proton bridge in the desktop window; `Remote(id)` is a
/// stable named target. Today browser remotes are relay devices reached over
/// WebSocket; the identity deliberately does not encode that transport so a
/// another remote target can use the same channel shape.
pub(all) enum ChannelId {
  Local
  Remote(String)
} derive(Debug, Eq, Hash)

///|
/// One conversation on one engine host. Session ids are only meaningful
/// inside their channel: two independent hosts may both contain `s1`, and
/// their state and async replies must remain distinct throughout the client.
/// This is a frontend identity only; neither the remote wire nor persistence
/// serializes this struct.
pub(all) struct ConversationKey {
  channel : ChannelId
  session : String
} derive(Debug, Eq, Hash)

///|
/// The complete directory placement of one conversation. Files and language
/// services use `checkout_root`; Git and terminal worktree resolution use
/// `project_root`. Keeping both projections on this single value prevents a
/// caller from combining a worktree name with an unrelated root.
///
/// `MissingWorktree` deliberately has no checkout root. It retains only the
/// registered project and durable worktree name, so every operating system
/// blocks path-based work without inventing a sentinel path.
pub(all) enum CheckoutPlacement {
  // OpenSeek scratch conversations expose their lazily-created directory;
  // cwd-less Codex tasks deliberately do not. Both still identify a scratch
  // terminal group, while only `Some(root)` enables Files and language work.
  Scratch(root~ : @common.Uri?)
  WorkspaceRoot(root~ : @common.Uri)
  Worktree(project~ : @common.Uri, name~ : String, root~ : @common.Uri)
  MissingWorktree(project~ : @common.Uri, name~ : String)
} derive(Debug, Eq)

///|
/// The concrete directory addressed by files, terminal processes, and
/// language services. A retained missing worktree has no directory.
pub fn CheckoutPlacement::checkout_root(
  self : CheckoutPlacement,
) -> @common.Uri? {
  match self {
    Scratch(root~) => root
    WorkspaceRoot(root~) | Worktree(root~, ..) => Some(root)
    MissingWorktree(..) => None
  }
}

///|
/// The registered project that owns this placement. Scratch conversations
/// are intentionally outside the project/worktree registry.
pub fn CheckoutPlacement::project_root(
  self : CheckoutPlacement,
) -> @common.Uri? {
  match self {
    Scratch(..) => None
    WorkspaceRoot(root~) => Some(root)
    Worktree(project~, ..) | MissingWorktree(project~, ..) => Some(project)
  }
}

///|
/// The durable registry name for worktree placements, including a checkout
/// that is currently missing.
pub fn CheckoutPlacement::worktree_name(self : CheckoutPlacement) -> String? {
  match self {
    Worktree(name~, ..) | MissingWorktree(name~, ..) => Some(name)
    Scratch(..) | WorkspaceRoot(..) => None
  }
}

///|
/// Whether path-based work can safely address this placement now.
pub fn CheckoutPlacement::is_ready(self : CheckoutPlacement) -> Bool {
  !(self is MissingWorktree(..))
}

///|
/// Whether two values describe the same durable checkout identity. Losing and
/// repairing one managed worktree does not change its identity, even though
/// the missing state temporarily has no root. Two simultaneously live
/// worktrees must also agree on their concrete root; a host-side move is a new
/// filesystem incarnation and must fence cached requests.
pub fn CheckoutPlacement::same_identity(
  self : CheckoutPlacement,
  other : CheckoutPlacement,
) -> Bool {
  match (self, other) {
    (Scratch(root=left), Scratch(root=right)) => left == right
    (WorkspaceRoot(root=left), WorkspaceRoot(root=right)) => left == right
    (
      Worktree(project=left_project, name=left_name, root=left_root),
      Worktree(project=right_project, name=right_name, root=right_root),
    ) =>
      left_project == right_project &&
      left_name == right_name &&
      left_root == right_root
    (
      Worktree(project=left_project, name=left_name, ..),
      MissingWorktree(project=right_project, name=right_name),
    )
    | (
      MissingWorktree(project=left_project, name=left_name),
      Worktree(project=right_project, name=right_name, ..),
    )
    | (
      MissingWorktree(project=left_project, name=left_name),
      MissingWorktree(project=right_project, name=right_name),
    ) => left_project == right_project && left_name == right_name
    _ => false
  }
}

///|
/// The authority used by app-owned resource URIs for this channel. The
/// authority is an identity, not a network endpoint: `remote.<id>` stays
/// stable if the target's transport changes.
pub fn ChannelId::uri_authority(self : ChannelId) -> String {
  match self {
    Local => "local"
    Remote(id) => "remote.\{id}"
  }
}

///|
/// Decode an app-owned URI authority. Unknown authorities and an empty remote
/// id are rejected so a foreign URI can never fall back to the local host.
pub fn ChannelId::from_uri_authority(authority : String) -> ChannelId? {
  if authority == "local" {
    Some(Local)
  } else if authority.strip_prefix("remote.") is Some(id) && !id.is_empty() {
    Some(Remote(id.to_owned()))
  } else {
    None
  }
}

///|
/// The channel this page is born with: the desktop webview talks to its
/// local host. `None` in a browser — the console at `/` holds no channel
/// until it fetches the device roster and connects each device.
pub fn page_channel() -> ChannelId? {
  if openseek_api() is Some(_) {
    Some(Local)
  } else {
    None
  }
}

///|
test "missing worktrees have no platform sentinel checkout root" {
  let project = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/C:/Users/alice/project",
  ) catch {
    _ => fail("Windows project URI fixture was invalid")
  }
  let placement = MissingWorktree(project~, name="wt-1")
  assert_true(placement.checkout_root() is None)
  assert_eq(placement.project_root(), Some(project))
  assert_false(placement.is_ready())
}

///|
test "a managed worktree keeps its identity while temporarily missing" {
  let project = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/project",
  ) catch {
    _ => fail("project URI fixture was invalid")
  }
  let root = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/worktrees/wt-1",
  ) catch {
    _ => fail("worktree URI fixture was invalid")
  }
  let live = Worktree(project~, name="wt-1", root~)
  let missing = MissingWorktree(project~, name="wt-1")
  assert_true(live.same_identity(missing))
  assert_true(missing.same_identity(live))
  assert_true(live.is_ready())
}

///|
pub extend ChannelId with Debug::{to_repr}

///|
pub extend ChannelId with Eq::{equal, not_equal}

///|
pub extend ChannelId with Hash::{hash, hash_combine}

///|
pub extend CheckoutPlacement with Debug::{to_repr}

///|
pub extend CheckoutPlacement with Eq::{equal, not_equal}

///|
pub extend ConversationKey with Debug::{to_repr}

///|
pub extend ConversationKey with Eq::{equal, not_equal}

///|
pub extend ConversationKey with Hash::{hash, hash_combine}
