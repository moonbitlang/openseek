// Frontend identity for files owned by an engine channel. Absolute host paths
// cross the protocol as slash-rooted URI path components; this package binds
// one to its channel and keeps every frontend path operation in URI space.

///|
/// The URI scheme for files owned by an OpenSeek engine channel. It is not a
/// `file` URI: the browser must never interpret a remote device's path using
/// the browser machine's filesystem rules.
pub const Scheme : String = "openseek"

///|
/// Bind a protocol resource path to the channel whose backend produced it.
/// The backend has already converted its native absolute path and rejected
/// UNC; this boundary independently rejects non-rooted and double-rooted
/// spellings before they can enter frontend state.
pub fn of_path(channel : @interop.ChannelId, path : String) -> @common.Uri? {
  guard path is ['/', ..] && !(path is ['/', '/', ..]) else { return None }
  let uri = @common.Uri::from(
    scheme=Scheme,
    authority=channel.uri_authority(),
    path~,
  ) catch {
    _ => return None
  }
  let normalized = @common.ext_uri.normalize_path(uri)
  // Viewer model ids and feedback handles serialize then parse this URI.
  // Canonicalize through that same public form now, so a Windows drive
  // (`/C:/...` -> `/c:/...`) cannot acquire a second frontend identity later.
  let canonical = @common.Uri::parse(normalized.to_string()) catch {
    _ => return None
  }
  Some(canonical)
}

///|
/// The engine channel named by this app-owned resource URI. Foreign schemes,
/// query/fragment-bearing addresses, and unknown authorities are rejected so
/// a document can never fall back to a different device.
pub fn channel(uri : @common.Uri) -> @interop.ChannelId? {
  guard uri.scheme == Scheme &&
    uri.query.is_empty() &&
    uri.fragment.is_empty() &&
    uri.path is ['/', ..] &&
    !(uri.path is ['/', '/', ..]) else {
    return None
  }
  @interop.ChannelId::from_uri_authority(uri.authority)
}

///|
/// Return the protocol path only when this resource belongs to `channel`.
/// Callers use this at the request boundary; checking the authority prevents
/// an accidentally retained URI from being sent to another device.
pub fn path_for(uri : @common.Uri, owner : @interop.ChannelId) -> String? {
  guard channel(uri) == Some(owner) else { return None }
  Some(uri.path)
}

///|
/// Whether this resource is owned by `owner`. Workspace payloads use this
/// before they are encoded for a request, so a URI retained from another
/// device can never be sent as this one's store.
pub fn belongs_to(uri : @common.Uri, owner : @interop.ChannelId) -> Bool {
  channel(uri) == Some(owner)
}

///|
/// Append one already-classified workspace-relative path to this resource.
/// URI joining uses slash semantics for the custom scheme and preserves the
/// scheme and device authority.
pub fn join_relative(uri : @common.Uri, child : @pathx.Relative) -> @common.Uri {
  @common.ext_uri.join_path(uri, [child.0])
}

///|
/// Whether `path` is this resource or a descendant of it. URI comparison
/// requires the same scheme and device authority before inspecting segments.
pub fn contains(root : @common.Uri, path : @common.Uri) -> Bool {
  channel(root) is Some(_) &&
  channel(path) is Some(_) &&
  @common.ext_uri.is_equal_or_parent(path, root)
}

///|
/// This resource relative to absolute resource `root`, or `None` when it is
/// on another device or outside that root.
pub fn relative_to(uri : @common.Uri, root : @common.Uri) -> @pathx.Relative? {
  guard contains(root, uri) else { return None }
  @common.ext_uri
  .relative_path(root, uri)
  .map(path => {
    if path.is_empty() {
      @pathx.Relative::root()
    } else {
      Relative(path)
    }
  })
}

///|
/// The last path component used as a workspace label. A URI root has no
/// basename, so retain its path spelling instead of substituting authority.
pub fn label(uri : @common.Uri) -> String {
  let label = @common.ext_uri.basename(uri)
  if label.is_empty() {
    uri.path
  } else {
    label
  }
}
