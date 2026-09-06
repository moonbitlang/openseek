// The folding feature's registrations — the contribution + action half of
// `vscode/src/vs/editor/contrib/folding/browser/folding.ts` (vscode
// checked-in submodule):
// `registerEditorContribution(FoldingController.ID, …, Eager)` plus the
// keyboard-reachable actions. Only `editor.fold` and `editor.unfold` are
// registered: the registry dispatches single (non-chord) keystrokes, and the
// source's remaining actions bind `Cmd+K` chords or exist for the command
// palette, neither of which the viewer has.

///|
fn register_folding_contribution(registry : EditorContributionRegistry) -> Unit {
  registry.register_editor_contribution(
    @folding_browser.FOLDING_CONTROLLER_ID,
    Folding,
    Eager,
    _viewer => Folding(FoldingController()),
    viewer => {
      let listeners : Array[@base_common.Disposable] = [
        // `this.editor.onDidChangeModel(() => this.onModelChanged())`
        viewer.on_did_change_model(_ => viewer.folding_on_model_changed()),
        // `this.editor.onDidChangeModelContent(e => this.onDidChangeModelContent(e))`
        // (`folding.ts`, the localToDispose set): recompute the regions against
        // the new content; `FoldingModel.update`'s region matching preserves
        // collapse state where ranges still match, and its decoration delta
        // tolerates the ids the flush destroyed.
        viewer.on_did_change_model_content(_ => {
          viewer.trigger_folding_model_changed()
        }),
        // `this.editor.onDidChangeCursorPosition(...)` (model-scoped in the
        // source; the viewer's cursor events already gate on a model)
        viewer.on_did_change_cursor_position(_ => {
          viewer.folding_on_cursor_position_changed()
        }),
        // `this.editor.onMouseDown/Up(...)`
        viewer.on_mouse_down(e => viewer.folding_on_editor_mouse_down(e)),
        viewer.on_mouse_up(e => viewer.folding_on_editor_mouse_up(e)),
      ]
      // the constructor's trailing `this.onModelChanged()`
      viewer.folding_on_model_changed()
      listeners
    },
  )
  // `editor.fold` (`folding.ts:718`): Ctrl/Cmd+Shift+BracketLeft. The
  // dispatch matches `KeyboardEvent.key`, so the rule covers both the base
  // `[` (synthetic events) and the shift-transformed `{` (US hardware).
  registry.register_editor_command(
    "editor.fold",
    viewer => viewer.folding_enabled(),
    viewer => viewer.folding_fold_action(),
    [],
    shift_keybindings=[("[", false, true), ("{", false, true)],
  )
  // `editor.unfold` (`folding.ts:635`): Ctrl/Cmd+Shift+BracketRight.
  registry.register_editor_command(
    "editor.unfold",
    viewer => viewer.folding_enabled(),
    viewer => viewer.folding_unfold_action(),
    [],
    shift_keybindings=[("]", false, true), ("}", false, true)],
  )
}

///|
/// `CONTEXT_FOLDING_ENABLED` (`folding.ts:46`) as a live predicate.
fn CodeEditorWidget::folding_enabled(self : CodeEditorWidget) -> Bool {
  self.is_code_presentation() &&
  self.get_options().folding &&
  self.folding_controller() is Some(controller) &&
  controller.folding_model is Some(_)
}

///|
/// `FoldingAction.getSelectedLines` (`folding.ts:571`).
fn CodeEditorWidget::folding_selected_lines(
  self : CodeEditorWidget,
) -> Array[Int] {
  self.get_selections().unwrap_or([]).map(s => s.start().line_number)
}

///|
/// The `FoldingAction.runEditorCommand` tail (`folding.ts:562-566`): after
/// the state change, keep the selection's start on screen.
fn CodeEditorWidget::folding_reveal_selection(self : CodeEditorWidget) -> Unit {
  match self.get_selection() {
    Some(selection) => self.folding_reveal(selection.start())
    None => ()
  }
}

///|
/// `FoldAction.invoke`'s no-arguments path (`folding.ts:770-777`): fold the
/// region at each selection, or if already collapsed, the first uncollapsed
/// parent instead.
fn CodeEditorWidget::folding_fold_action(self : CodeEditorWidget) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  guard controller.folding_model is Some(folding_model) else { return }
  @folding_browser.set_collapse_state_up(
    folding_model,
    true,
    self.folding_selected_lines(),
  )
  self.folding_reveal_selection()
}

///|
/// `UnfoldAction.invoke`'s no-arguments path (`folding.ts:688-695`): unfold
/// one level at each selection.
fn CodeEditorWidget::folding_unfold_action(self : CodeEditorWidget) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  guard controller.folding_model is Some(folding_model) else { return }
  @folding_browser.set_collapse_state_levels_down(
    folding_model,
    false,
    levels=1,
    line_numbers=self.folding_selected_lines(),
  )
  self.folding_reveal_selection()
}
