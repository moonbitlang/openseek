///|
/// Root-supplied operations and viewer-scoped telemetry emitters. This lower
/// package deliberately knows a viewer only by its stable public id and
/// callback surface, keeping the dependency direction toward root one-way.
priv struct ViewerTestingEntry {
  registration_id : Int
  set_hidden_areas : (Array[@base_common.Range], String?, Bool) -> Unit
  did_build_view_model : @base_common.Emitter[ViewModelBuiltObservation]
  did_render_model : @base_common.Emitter[ModelRenderedObservation]
  did_resolve_hover : @base_common.Emitter[HoverResolvedObservation]
}

///|
let viewer_entries : Map[String, ViewerTestingEntry] = Map([])

///|
let next_registration_id : Ref[Int] = Ref(0)

///|
fn ViewerTestingEntry::dispose(self : ViewerTestingEntry) -> Unit {
  self.did_build_view_model.dispose()
  self.did_render_model.dispose()
  self.did_resolve_hover.dispose()
}

///|
fn unregister_if_current(viewer_id : String, registration_id : Int) -> Unit {
  match viewer_entries.get(viewer_id) {
    Some(entry) if entry.registration_id == registration_id => {
      viewer_entries.remove(viewer_id)
      entry.dispose()
    }
    _ => ()
  }
}

///|
/// Registers one live viewer's test controls. Re-registering an id disposes
/// the previous entry and its listeners. The returned disposable is
/// generation-aware: disposing an older registration cannot remove a newer
/// viewer that happens to reuse the same id.
pub fn register_viewer(
  viewer_id : String,
  set_hidden_areas~ : (Array[@base_common.Range], String?, Bool) -> Unit,
) -> @base_common.Disposable {
  unregister_viewer(viewer_id)
  next_registration_id.val += 1
  let registration_id = next_registration_id.val
  viewer_entries[viewer_id] = {
    registration_id,
    set_hidden_areas,
    did_build_view_model: Emitter(),
    did_render_model: Emitter(),
    did_resolve_hover: Emitter(),
  }
  offer_browser_hidden_lines_diagnostic(set_hidden_lines_for_browser_diagnostic)
  @base_common.Disposable::from(() => {
    unregister_if_current(viewer_id, registration_id)
  })
}

///|
/// Removes one viewer's controls and all of its testing listeners. Unknown or
/// already-removed ids are no-ops.
fn unregister_viewer(viewer_id : String) -> Unit {
  match viewer_entries.get(viewer_id) {
    Some(entry) => {
      viewer_entries.remove(viewer_id)
      entry.dispose()
    }
    None => ()
  }
}

///|
/// Applies hidden areas through a registered viewer's private control seam.
/// Returns `false` when the id has already been unregistered.
fn set_hidden_areas(
  viewer_id : String,
  ranges : Array[@base_common.Range],
  source? : String,
  force_update? : Bool = false,
) -> Bool {
  match viewer_entries.get(viewer_id) {
    Some(entry) => {
      (entry.set_hidden_areas)(ranges, source, force_update)
      true
    }
    None => false
  }
}

///|
/// Primitive-only browser bridge for exercising the private hidden-area path
/// without publishing `set_hidden_areas` as MoonBit API. Viewer lookup stays
/// in the generation-aware registry, so disposed and reused ids remain safe.
fn set_hidden_lines_for_browser_diagnostic(
  viewer_id : String,
  start_line : Int,
  end_line : Int,
  source : String,
  hidden : Bool,
) -> Bool {
  let ranges = if hidden {
    [@base_common.Range(start_line, 1, end_line, 1)]
  } else {
    []
  }
  set_hidden_areas(viewer_id, ranges, source~)
}

///|
/// Product hosts do not install the optional probe, leaving the private
/// control absent from their JavaScript surface as well as MoonBit's API.
extern "js" fn offer_browser_hidden_lines_diagnostic(
  set_hidden_lines : (String, Int, Int, String, Bool) -> Bool,
) -> Unit =
  #| (setHiddenLines) => globalThis.__viewerPrivateTestProbe?.acceptSetHiddenLines?.(setHiddenLines)

///|
/// Subscribes to view-model-build observations for one registered viewer.
/// Missing or unregistered ids return an inert disposable.
pub fn on_did_build_view_model(
  viewer_id : String,
  listener : (ViewModelBuiltObservation) -> Unit,
) -> @base_common.Disposable {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_build_view_model.event(listener)
    None => @base_common.Disposable::from(() => ())
  }
}

///|
/// Subscribes to model-render observations for one registered viewer.
/// Missing or unregistered ids return an inert disposable.
pub fn on_did_render_model(
  viewer_id : String,
  listener : (ModelRenderedObservation) -> Unit,
) -> @base_common.Disposable {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_render_model.event(listener)
    None => @base_common.Disposable::from(() => ())
  }
}

///|
/// Subscribes to hover-resolution observations for one registered viewer.
/// Missing or unregistered ids return an inert disposable.
pub fn on_did_resolve_hover(
  viewer_id : String,
  listener : (HoverResolvedObservation) -> Unit,
) -> @base_common.Disposable {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_resolve_hover.event(listener)
    None => @base_common.Disposable::from(() => ())
  }
}

///|
/// Publishes one view-model-build observation to the matching live viewer.
pub fn has_view_model_built_listeners(viewer_id : String) -> Bool {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_build_view_model.has_listeners()
    None => false
  }
}

///|
/// Publishes one view-model-build observation to the matching live viewer.
pub fn publish_view_model_built(
  viewer_id : String,
  observation : ViewModelBuiltObservation,
) -> Unit {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_build_view_model.fire(observation)
    None => ()
  }
}

///|
/// Publishes one model-render observation to the matching live viewer.
pub fn publish_model_rendered(
  viewer_id : String,
  observation : ModelRenderedObservation,
) -> Unit {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_render_model.fire(observation)
    None => ()
  }
}

///|
/// Publishes one hover-resolution observation to the matching live viewer.
pub fn publish_hover_resolved(
  viewer_id : String,
  observation : HoverResolvedObservation,
) -> Unit {
  match viewer_entries.get(viewer_id) {
    Some(entry) => entry.did_resolve_hover.fire(observation)
    None => ()
  }
}
