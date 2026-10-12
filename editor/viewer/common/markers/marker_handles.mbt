///|
/// Borrowed marker-store capabilities required by `MarkerDecorationsService`.
/// The concrete store remains caller-owned; this adapter exposes only the
/// change subscription, filtered read, and removal operations used by the
/// decoration projection.
struct MarkerServiceHandle {
  on_did_change_markers : ((Array[@base_common.Uri]) -> Unit) -> @base_common.Disposable
  read : (MarkerReadOptions) -> Array[Marker]
  remove : (String, Array[@base_common.Uri]) -> Unit
}

///|
/// Narrows a concrete marker store to the capabilities required by the
/// decorations adapter. Disposing the handle's returned subscriptions never
/// disposes the caller-owned store.
pub fn MarkerService::marker_service_handle(
  self : MarkerService,
) -> MarkerServiceHandle {
  {
    on_did_change_markers: listener => self.on_did_change_markers(listener),
    read: options => self.read(options),
    remove: (owner, resources) => self.remove(owner, resources),
  }
}

///|
/// Subscribes to marker-store changes through the borrowed adapter.
fn MarkerServiceHandle::on_did_change_markers(
  self : MarkerServiceHandle,
  listener : (Array[@base_common.Uri]) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_markers)(listener)
}

///|
/// Reads markers through the borrowed adapter.
fn MarkerServiceHandle::read(
  self : MarkerServiceHandle,
  options : MarkerReadOptions,
) -> Array[Marker] {
  (self.read)(options)
}

///|
/// Removes the owner's markers for the supplied resources through the borrowed
/// adapter.
fn MarkerServiceHandle::remove(
  self : MarkerServiceHandle,
  owner : String,
  resources : Array[@base_common.Uri],
) -> Unit {
  (self.remove)(owner, resources)
}

///|
/// Production marker-decoration capabilities consumed by Viewer and editor
/// contributions. The concrete decoration service retains lifecycle ownership;
/// leases and subscriptions returned here remain independently disposable.
pub struct ResolvedMarkerDecoration {
  range : @base_common.Range
  marker : Marker
  options : @model.ModelDecorationOptions
}

///|
/// Matches the Code decorations overlay's observable ordering: z-index,
/// JavaScript UTF-16 lexicographic class name, then range start.
fn compare_resolved_marker_decorations(
  left : ResolvedMarkerDecoration,
  right : ResolvedMarkerDecoration,
) -> Int32 {
  if left.options.z_index != right.options.z_index {
    return left.options.z_index - right.options.z_index
  }
  let class_order = @base_common.compare(
    left.options.class_name,
    right.options.class_name,
  )
  if class_order != 0 {
    return class_order
  }
  @base_common.Range::compare_ranges_using_starts(left.range, right.range)
}

///|
struct MarkerDecorationsHandle {
  acquire_model : (@model.TextModel) -> @base_common.Disposable
  on_did_change_marker_decorations : ((@model.TextModel) -> Unit) -> @base_common.Disposable
  get_live_markers_for_model : (@model.TextModel) -> Array[
    (@base_common.Range, Marker),
  ]
  get_live_resolved_marker_decorations_for_model : (@model.TextModel) -> Array[
    ResolvedMarkerDecoration,
  ]
}

///|
/// Narrows a concrete decoration service to the production Viewer surface.
pub fn MarkerDecorationsService::marker_decorations_handle(
  self : MarkerDecorationsService,
) -> MarkerDecorationsHandle {
  {
    acquire_model: model => self.acquire_model(model),
    on_did_change_marker_decorations: listener => {
      self.on_did_change_marker_decorations(listener)
    },
    get_live_markers_for_model: model => self.get_live_markers_for_model(model),
    get_live_resolved_marker_decorations_for_model: model => {
      let resolved : Array[ResolvedMarkerDecoration] = []
      for pair in self.get_live_markers_for_model(model) {
        let (range, marker) = pair
        resolved.push({
          range,
          marker,
          options: create_decoration_option(marker),
        })
      }
      resolved.sort_by(compare_resolved_marker_decorations)
      resolved
    },
  }
}

///|
/// Acquires one model-scoped decoration lease.
pub fn MarkerDecorationsHandle::acquire_model(
  self : MarkerDecorationsHandle,
  model : @model.TextModel,
) -> @base_common.Disposable {
  (self.acquire_model)(model)
}

///|
/// Subscribes to changes in live marker decorations.
pub fn MarkerDecorationsHandle::on_did_change_marker_decorations(
  self : MarkerDecorationsHandle,
  listener : (@model.TextModel) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_marker_decorations)(listener)
}

///|
/// Returns live marker decorations for this exact model identity.
pub fn MarkerDecorationsHandle::get_live_markers_for_model(
  self : MarkerDecorationsHandle,
  model : @model.TextModel,
) -> Array[(@base_common.Range, Marker)] {
  (self.get_live_markers_for_model)(model)
}

///|
/// Returns the same live, exact-model entries together with the decoration
/// options already resolved by the marker package's single severity/tag
/// policy and sorted in Code-overlay paint order. Alternate DOM presentations
/// consume these values rather than rebuilding a parallel marker store,
/// severity matrix, or overlap order.
pub fn MarkerDecorationsHandle::get_live_resolved_marker_decorations_for_model(
  self : MarkerDecorationsHandle,
  model : @model.TextModel,
) -> Array[ResolvedMarkerDecoration] {
  (self.get_live_resolved_marker_decorations_for_model)(model)
}

///|
/// Closed marker backing accepted by `ViewerServices`: either a caller-owned
/// store from which the bundle creates its decorations adapter, or an already
/// adapted caller-owned decoration service.
pub(all) enum MarkerDecorationsSource {
  MarkerStore(MarkerServiceHandle)
  Decorations(MarkerDecorationsHandle)
}
