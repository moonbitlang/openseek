// The public decoration API slice of Monaco's `codeEditorWidget.ts`
// (decoration plan Phase 5), checked-in vscode submodule:
// `deltaDecorations` (:1368), `removeDecorations` (:1380),
// `getLineDecorations` (:1342), `getDecorationsInRange` (:1350).
//
// Deviations: the no-model `null` returns are empty arrays (MoonBit
// signatures stay non-optional, matching the viewer's public read API
// conventions); `filterFontDecorations` is constantly false (font
// decorations out of scope).

///|
/// `deltaDecorations` (`codeEditorWidget.ts:1368-1378`): atomically replace
/// `old_decorations` (ids) with `new_decorations`, owned by this viewer
/// (`ownerId` = the viewer's editor id). Returns the new decoration ids.
/// ModelDecorationOptions state lives on the model, so it follows the model across
/// `set_model` swaps like Monaco's — re-apply on swap.
pub fn CodeEditorWidget::delta_decorations(
  self : CodeEditorWidget,
  old_decorations : Array[String],
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  guard self.get_model() is Some(model) else { return [] }
  if old_decorations.length() == 0 && new_decorations.length() == 0 {
    return old_decorations
  }
  model.delta_decorations(
    old_decorations,
    new_decorations,
    owner_id=self.editor_id,
  )
}

///|
/// `removeDecorations` (`codeEditorWidget.ts:1380-1387`): delta to empty
/// through one `change_decorations` bracket.
pub fn CodeEditorWidget::remove_decorations(
  self : CodeEditorWidget,
  decoration_ids : Array[String],
) -> Unit {
  guard self.get_model() is Some(model) && decoration_ids.length() > 0 else {
    return
  }
  model.change_decorations(accessor => {
    ignore((accessor.delta_decorations)(decoration_ids, []))
  })
}

///|
/// Monaco's `IEditorDecorationsCollection` (`editorCommon.ts:544`), the
/// non-deprecated decoration entry point: an id-managing wrapper over
/// `delta_decorations` bound to one viewer. `onDidChange` and `has` are not
/// ported (no consumer; the model-decoration event seam stays internal).
struct EditorDecorationsCollection {
  viewer : CodeEditorWidget
  mut decoration_ids : Array[String]
}

///|
/// `createDecorationsCollection` (`codeEditorWidget.ts:1389`).
pub fn CodeEditorWidget::create_decorations_collection(
  self : CodeEditorWidget,
  decorations~ : Array[@model.ModelDeltaDecoration] = [],
) -> EditorDecorationsCollection {
  let collection : EditorDecorationsCollection = {
    viewer: self,
    decoration_ids: [],
  }
  if decorations.length() > 0 {
    collection.set(decorations) |> ignore
  }
  collection
}

///|
/// Removes every decoration in the collection.
pub fn EditorDecorationsCollection::clear(
  self : EditorDecorationsCollection,
) -> Unit {
  self.decoration_ids = self.viewer.delta_decorations(self.decoration_ids, [])
}
