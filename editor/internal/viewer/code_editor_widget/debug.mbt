// Root-private instrumentation remains only for white-box assertions. Browser
// tests and the workbench subscribe through the CodeEditorWidget-id-keyed
// `internal/viewer/browser/testing` registry, so none of these hooks or
// payloads leak through the public CodeEditorWidget facade.

///|
/// Fires after a model's content is prepared for rendering (view-model build
/// at attach, token re-warm on tokenizer changes) — tokenize/build timings
/// and counts for telemetry and test synchronization.
fn debug_on_did_build_view_model(
  viewer : CodeEditorWidget,
  listener : (@viewer_testing.ViewModelBuiltObservation) -> Unit,
) -> @base_common.Disposable {
  viewer.did_build_view_model.event(listener)
}

///|
/// White-box-only seam retained in the ordinary library build.
let _debug_build_test_seam_anchor : Unit = ignore(debug_on_did_build_view_model)

///|
fn CodeEditorWidget::has_view_model_built_listeners(
  self : CodeEditorWidget,
) -> Bool {
  self.did_build_view_model.has_listeners() ||
  @viewer_testing.has_view_model_built_listeners(self.get_id())
}

///|
fn CodeEditorWidget::emit_view_model_built(
  self : CodeEditorWidget,
  observation : @viewer_testing.ViewModelBuiltObservation,
) -> Unit {
  self.did_build_view_model.fire(observation)
  @viewer_testing.publish_view_model_built(self.get_id(), observation)
}

///|
fn CodeEditorWidget::emit_model_rendered(
  self : CodeEditorWidget,
  observation : @viewer_testing.ModelRenderedObservation,
) -> Unit {
  @viewer_testing.publish_model_rendered(self.get_id(), observation)
}

///|
fn CodeEditorWidget::emit_hover_resolved(
  self : CodeEditorWidget,
  observation : @viewer_testing.HoverResolvedObservation,
) -> Unit {
  @viewer_testing.publish_hover_resolved(self.get_id(), observation)
}
