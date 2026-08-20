///|
/// Display mode for the one shared Peek owner. Definition requests and the
/// precomputed-references entry use the same shell and lifetime.
pub(all) enum ReferencesPeekMode {
  Definitions
  References
} derive(Eq, Debug)

///|
/// Logical lifecycle of the shared Peek session. Browser and model-reference
/// resources stay with the root Viewer and are keyed by these generations.
pub(all) enum ReferencesPeekPhase {
  PeekClosed
  PeekLoadingDefinitions(Int)
  PeekLoadingReferences(Int)
  PeekLoadingPreview(Int, Int)
  PeekShown(Int, Int)
  PeekUnavailable(Int, Int)
} derive(Eq, Debug)

///|
/// Exact source identity for toggling and freshness checks. The attachment
/// generation distinguishes repeated attachment of the same physical model;
/// the content version distinguishes edits within one attachment.
pub struct ReferencesSessionKey {
  model_identity : Int
  model_generation : Int
  model_version_id : Int
  anchor : @base_common.Position
} derive(Eq, Debug)

///|
pub fn ReferencesSessionKey::from_model(
  model : @model.TextModel,
  model_generation : Int,
  anchor : @base_common.Position,
) -> ReferencesSessionKey {
  {
    model_identity: model.identity(),
    model_generation,
    model_version_id: model.get_version_id(),
    anchor,
  }
}

///|
/// Whether the model identity, attachment, and content captured by this key
/// remain current. Exact-anchor equality is represented by `Eq` on the key.
pub fn ReferencesSessionKey::is_current(
  self : ReferencesSessionKey,
  model : @model.TextModel,
  model_generation : Int,
) -> Bool {
  self.model_identity == model.identity() &&
  self.model_generation == model_generation &&
  self.model_version_id == model.get_version_id() &&
  !model.is_disposed()
}

///|
#deprecated
pub extend ReferencesPeekMode with Debug::{to_repr}

///|
pub extend ReferencesPeekMode with Eq::{equal, not_equal}

///|
#deprecated
pub extend ReferencesPeekPhase with Debug::{to_repr}

///|
pub extend ReferencesPeekPhase with Eq::{equal, not_equal}

///|
#deprecated
pub extend ReferencesSessionKey with Debug::{to_repr}

///|
pub extend ReferencesSessionKey with Eq::{equal, not_equal}
