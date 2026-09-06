// The quick-diff feature's registration — the role of
// `vscode/src/vs/workbench/contrib/scm/browser/quickDiff.contribution.ts`
// plus `QuickDiffWorkbenchController`'s editor tracking (vscode submodule
// checked-in source), reduced to the editor-contribution registry: the
// controller upstream watches the editor service and attaches a
// `QuickDiffDecorator` per (resource, editor); the viewer's registry
// already instantiates per editor, so the contribution body IS the
// decorator wiring. The controller's configuration surface
// (`scm.diffDecorations*`) is N-A (defaults are baked into
// `quick_diff.css`); the peek widget and its actions are not ported.

///|
fn register_quick_diff_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    "quickDiff.decorator",
    QuickDiff,
    Eager,
    viewer => {
      QuickDiff(
        QuickDiffContributionState(viewer.create_decorations_collection()),
      )
    },
    viewer => {
      let state = match viewer.quick_diff_contribution() {
        Some(state) => state
        None => abort("quick-diff contribution variant mismatch")
      }
      // `QuickDiffWorkbenchController.onEditorsChanged` re-evaluates the
      // decorator when an editor's model changes.
      state.listeners.push(
        viewer.on_did_change_model(_ => {
          viewer.quick_diff_update(state.collection)
        }),
      )
      // `QuickDiffModel`'s recompute on modified-side content changes
      // (`onDidChangeContent` → `triggerDiff`): a `set_value` flush both
      // changes the diff input and destroys the collection's decorations, so
      // the decorator re-runs against the new snapshot.
      state.listeners.push(
        viewer.on_did_change_model_content(_ => {
          viewer.quick_diff_update(state.collection)
        }),
      )
      // `QuickDiffModel`'s recompute on quick-diff (provider/original) changes,
      // scoped to this editor's resource.
      state.listeners.push(
        viewer.services.quick_diff.on_did_change_original(resource => {
          if viewer.get_model() is Some(model) &&
            model.uri.to_string() == resource.to_string() {
            viewer.quick_diff_update(state.collection)
          }
        }),
      )
      viewer.quick_diff_update(state.collection)
      []
    },
  )
}

///|
/// Typed view over the central contribution row. Quick diff has no feature
/// package singleton: this state is owned only by `CodeEditorWidget.contributions`.
fn CodeEditorWidget::quick_diff_contribution(
  self : CodeEditorWidget,
) -> QuickDiffContributionState? {
  match self.contributions.lookup("quickDiff.decorator") {
    Some(entry) =>
      match entry.instance {
        QuickDiff(state) => Some(state)
        _ => None
      }
    _ => None
  }
}
