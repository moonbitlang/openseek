// Deliberate external/staged contracts without non-test construction in this
// repository. Their public layouts make the surviving marker input/output APIs
// usable while keeping the analyzer exception explicit in `exports.mbt`.

///|
/// Builds lower-level marker-shaped input for hosts that already own this
/// representation.
pub fn MarkerData::MarkerData(
  severity~ : MarkerSeverity,
  message~ : String,
  start_line_number~ : Int,
  start_column~ : Int,
  end_line_number~ : Int,
  end_column~ : Int,
  code? : String,
  source? : String,
  model_version_id? : Int,
  related_information? : Array[RelatedInformation],
  tags? : Array[MarkerTag],
  origin? : String,
) -> MarkerData {
  new_marker_data(
    severity~,
    message~,
    start_line_number~,
    start_column~,
    end_line_number~,
    end_column~,
    code?,
    source?,
    model_version_id?,
    related_information?,
    tags?,
    origin?,
  )
}

///|
/// Replaces one owner's lower-level markers for one resource.
pub fn MarkerService::change_one(
  self : MarkerService,
  owner : String,
  resource : @base_common.Uri,
  marker_data : Array[MarkerData],
) -> Unit {
  self.change_one_impl(owner, resource, marker_data)
}

///|
/// Related-information location, `IRelatedInformation` (`markers.ts:42`).
pub(all) struct RelatedInformation {
  resource : @base_common.Uri
  message : String
  start_line_number : Int
  start_column : Int
  end_line_number : Int
  end_column : Int
} derive(Eq, Debug)

///|
/// A `{resource, marker}` pair for `change_all`, `IResourceMarker`
/// (`markers.ts:124`).
pub(all) struct ResourceMarker {
  resource : @base_common.Uri
  marker : MarkerData
} derive(Eq, Debug)

///|
/// Compatibility entry point for callers that still use the historical
/// paired add/remove API. New viewer ownership uses `acquire_model` directly.
/// A repeated add refreshes the existing owner and never increments its lease.
pub fn MarkerDecorationsService::on_model_added(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Unit {
  if self.disposed {
    return
  }
  let model_id = model.identity()
  match self.model_registrations.get(model_id) {
    Some(_) => self.refresh_model_registration(model_id)
    None => {
      let lease = self.acquire_model(model)
      if self.model_registrations.contains(model_id) {
        self.legacy_leases.set(model_id, lease)
      }
    }
  }
}

///|
/// Compatibility counterpart to `on_model_added`. Ordinary paired removal is
/// a lease release and therefore never deletes host-owned diagnostics.
pub fn MarkerDecorationsService::on_model_removed(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Unit {
  let model_id = model.identity()
  match self.legacy_leases.get(model_id) {
    Some(lease) => {
      self.legacy_leases.remove(model_id)
      lease.dispose()
    }
    None => ()
  }
}

///|
/// Compatibility shim that clears markers from every owner for one resource.
pub fn MarkerService::clear_resource(
  self : MarkerService,
  resource : @base_common.Uri,
) -> Unit {
  for owner in self.read(MarkerReadOptions(resource~)).map(m => m.owner) {
    self.remove(owner, [resource])
  }
}

///|
/// Compatibility shim returning markers for one resource, optionally capped.
pub fn MarkerService::markers_for_resource(
  self : MarkerService,
  resource : @base_common.Uri,
  limit? : Int = 0,
) -> Array[Marker] {
  self.read(MarkerReadOptions(resource~, take=limit))
}

///|
pub extend RelatedInformation with Debug::{to_repr}

///|
pub extend RelatedInformation with Eq::{equal, not_equal}

///|
pub extend ResourceMarker with Debug::{to_repr}

///|
pub extend ResourceMarker with Eq::{equal, not_equal}
