// The editor-side half of `vscode/src/vs/workbench/contrib/scm/browser/
// quickDiffDecorator.ts` (checked-in vscode submodule): what
// `QuickDiffDecorator` does with its `codeEditor` — own a decorations
// collection and refill it from the quick-diff changes. The `CodeEditorWidget`-touching
// body lives here as root composition glue; the pure pieces (change
// computation and decoration construction) live in
// `internal/viewer/contrib/quick_diff/`. Those packages are dependencies of
// `viewer` and cannot import the facade back without creating a package cycle.

///|
/// Recomputes the quick-diff gutter decorations for the current model. The
/// source splits this across `QuickDiffModel`'s throttled recompute and
/// `QuickDiffDecorator.onDidChange`; the viewer's models are immutable and
/// the service stores one original per resource, so both collapse into one
/// synchronous pass: no model, or no stored original for it, clears the
/// collection (the decorator disposal path upstream).
fn CodeEditorWidget::quick_diff_update(
  self : CodeEditorWidget,
  collection : EditorDecorationsCollection,
) -> Unit {
  guard self.is_code_presentation() &&
    self.get_model() is Some(model) &&
    self.services.quick_diff.get_original_content(model.uri) is Some(original) else {
    collection.set([]) |> ignore
    return
  }
  let changes = @quick_diff_browser.compute_changes(
    @base_common.split_lines(original),
    model.get_lines_content(),
  )
  collection.set(@quick_diff_browser.changes_to_decorations(changes)) |> ignore
}
