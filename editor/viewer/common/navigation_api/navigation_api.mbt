///|
/// Host-neutral intent for opening a definition location. The mode deliberately
/// carries no tab, editor-group, workspace, or history policy.
pub(all) enum OpenLocationMode {
  Current
  Side
} derive(Eq, Debug)

///|
/// One request for the host to open a location that the initiating Viewer
/// cannot reveal locally. `source_viewer_id` is the stable public Viewer id;
/// concrete Viewer and shell types do not cross this common-package boundary.
pub(all) struct OpenLocationRequest {
  source_viewer_id : String
  location : @language.Location
  mode : OpenLocationMode
} derive(Debug)

///|
/// Minimal host-owned capability for opening a location. `true` means the host
/// accepted and handled the request; `false` leaves the initiating Viewer
/// unchanged so it can present non-destructive feedback.
struct LocationOpenerHandle {
  open_callback : async (OpenLocationRequest) -> Bool noraise
}

///|
/// Constructs an opener handle without transferring ownership of its captured
/// backing or lifecycle to the handle or ViewerServices.
pub fn LocationOpenerHandle::LocationOpenerHandle(
  open~ : async (OpenLocationRequest) -> Bool noraise,
) -> LocationOpenerHandle {
  { open_callback: open }
}

///|
pub async fn LocationOpenerHandle::open(
  self : LocationOpenerHandle,
  request : OpenLocationRequest,
) -> Bool noraise {
  (self.open_callback)(request)
}

///|
/// Caller-owned lease for a resolved preview model. The host keeps `model`
/// usable until `dispose` releases the lease. Disposing this reference never
/// disposes the TextModel itself.
struct TextModelReference {
  model_value : @model.TextModel
  release_callback : () -> Unit
  mut disposed : Bool
}

///|
/// Constructs a model lease from the exact caller-owned model and one release
/// callback. The callback is invoked at most once, including under repeated or
/// reentrant disposal.
pub fn TextModelReference::TextModelReference(
  model : @model.TextModel,
  release~ : () -> Unit,
) -> TextModelReference {
  { model_value: model, release_callback: release, disposed: false }
}

///|
/// Returns the caller-owned model retained by this lease.
pub fn TextModelReference::model(self : TextModelReference) -> @model.TextModel {
  self.model_value
}

///|
/// Releases the host lease exactly once without disposing its TextModel.
pub fn TextModelReference::dispose(self : TextModelReference) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  (self.release_callback)()
}

///|
/// Minimal dependency-inversion capability for resolving a cross-resource Peek
/// preview. The captured host decides whether the model comes from an existing
/// cache, a workspace, a file, or a network service. `None` means that no
/// preview is available.
struct TextModelResolverHandle {
  resolve_callback : async (@base_common.Uri, @language.CancellationToken) -> TextModelReference? noraise
}

///|
/// Constructs a resolver handle without transferring ownership of its captured
/// backing or lifecycle to the handle or ViewerServices.
pub fn TextModelResolverHandle::TextModelResolverHandle(
  resolve~ : async (@base_common.Uri, @language.CancellationToken) -> TextModelReference? noraise,
) -> TextModelResolverHandle {
  { resolve_callback: resolve }
}

///|
/// Resolves one resource using the caller's cooperative cancellation token.
/// The handle forwards the token unchanged; request-generation and stale-result
/// policy remain with the Peek controller.
pub async fn TextModelResolverHandle::resolve(
  self : TextModelResolverHandle,
  resource : @base_common.Uri,
  token : @language.CancellationToken,
) -> TextModelReference? noraise {
  (self.resolve_callback)(resource, token)
}

///|
pub extend OpenLocationMode with Debug::{to_repr}

///|
pub extend OpenLocationMode with Eq::{equal, not_equal}

///|
pub extend OpenLocationRequest with Debug::{to_repr}
