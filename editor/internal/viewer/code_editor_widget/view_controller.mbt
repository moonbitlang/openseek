///|
/// Maps a pointer gesture to a `CoreNavigationCommands` call on the cursor
/// stack — Monaco's `ViewController.dispatchMouse`
/// (`vscode/src/vs/editor/browser/view/viewController.ts:217-311`, vscode
/// checked-in submodule), branch for
/// branch over the full `IMouseDispatchData` (`@controller.MouseDispatchData`;
/// `data.position` is a 1-based view position).
///
/// Omitted branches (each an explicit early-out below, ledger):
///   * `middleButton` — no `ColumnSelect` command and no middle-click-scroll
///     contribution (viewController.ts:222-227);
///   * every `_hasMulticursorModifier` arm (`multiCursorModifier` reads as
///     the Monaco default `altKey`; the viewer's cursor stack is
///     single-cursor: no `_createCursor`/`_lastCursor*`,
///     viewController.ts:230-235, 246-251, 261-262, 282-294);
///   * `doubleClickSelectsBlock` (viewController.ts:267-278) — option not
///     modeled, no bracket-pair/tokenization query surface;
///   * `columnSelection` / alt-drag column select (viewController.ts:297-302)
///     — no column selection.
fn CodeEditorWidget::dispatch_mouse(
  self : CodeEditorWidget,
  data : @controller.MouseDispatchData,
) -> Unit {
  guard self.get_view_model() is Some(view_model) else { return }
  let old_cursor_state = view_model.cursor.get_primary_cursor_state()
  let position = validate_mouse_view_position(view_model, data.position)
  let command_args = CursorMoveCommandArgs::CursorMoveCommandArgs(
    source="mouse",
    position=self.view_to_model(position),
    view_position=position,
    reveal_type=data.reveal_type,
  )
  if data.middle_button {
    // `middleButton && !selectionClipboardIsOn` → middle-click scroll /
    // column select, both unported: a middle-button gesture must not fall
    // into the left-button arms.
    ()
  } else if data.started_on_line_numbers {
    // If the dragging started on the gutter, then have operations work on
    // the entire line
    if has_multicursor_modifier(data) {
      // `_lastCursorLineSelect` / `_createCursor` (multi-cursor) — unported.
      ()
    } else if data.in_selection_mode {
      self.run_line_core_command(view_model, Some(command_args), true) |> ignore
    } else {
      self.run_line_core_command(view_model, Some(command_args), false)
      |> ignore
    }
  } else if data.mouse_down_count >= 4 {
    self.run_select_all_core_command(nominal_source="mouse") |> ignore
  } else if data.mouse_down_count == 3 {
    if has_multicursor_modifier(data) {
      // `_lastCursorLineSelect(Drag)` — unported.
      ()
    } else if data.in_selection_mode {
      self.run_line_core_command(view_model, Some(command_args), true) |> ignore
    } else {
      self.run_line_core_command(view_model, Some(command_args), false)
      |> ignore
    }
  } else if data.mouse_down_count == 2 {
    // A double-click on injected text selects nothing
    // (viewController.ts:260).
    if !data.on_injected_text {
      if has_multicursor_modifier(data) {
        // `_lastCursorWordSelect` — unported.
        ()
      } else if data.in_selection_mode {
        self.run_word_core_command(view_model, Some(command_args), true)
        |> ignore
      } else {
        // `doubleClickSelectsBlock` bracket/string block select — unported.
        self.run_word_core_command(view_model, Some(command_args), false)
        |> ignore
      }
    }
  } else if has_multicursor_modifier(data) {
    // Purely-alt multi-cursor operations and the shift+alt column select —
    // unported (`!_hasNonMulticursorModifier` inner gate included).
    ()
  } else if data.in_selection_mode {
    if data.alt_key {
      // alt-drag column select — unported.
      ()
    } else {
      // `columnSelection` reads as the Monaco default `false`.
      self.run_move_to_core_command(view_model, Some(command_args), true)
      |> ignore
    }
  } else {
    self.run_move_to_core_command(view_model, Some(command_args), false)
    |> ignore
  }
  // Ordinary model-side changes schedule through the outgoing cursor relay.
  // A normalized view-side move can keep the same model selection under
  // injected text while changing the authoritative view position, so it has
  // no public event to trigger that relay. Compare the full paired state here
  // and schedule exactly that otherwise-silent repaint; deferred/no-op mouse
  // branches remain render no-ops.
  if view_model.cursor.get_primary_cursor_state() != old_cursor_state {
    self.schedule_render()
  }
}

///|
/// `_validateViewColumn` (`viewController.ts:101-107`): pointer targets below
/// the current view line's minimum column clamp up; every other target is
/// retained byte-for-byte. Hit testing already supplies a valid view line.
fn validate_mouse_view_position(
  view_model : @view_model.ViewModel,
  position : @base_common.Position,
) -> @base_common.Position {
  let min_column = view_model.get_line_min_column(position.line_number)
  if position.column < min_column {
    Position(position.line_number, min_column)
  } else {
    position
  }
}

///|
/// `_hasMulticursorModifier` (viewController.ts:109-120) with
/// `multiCursorModifier` at its Monaco default `'altKey'`.
fn has_multicursor_modifier(data : @controller.MouseDispatchData) -> Bool {
  data.alt_key
}

///|
/// `CoreNavigationCommands.SelectAll`: no view is an early return; otherwise
/// select the whole document with the source's hard-coded `keyboard` source.
/// The readonly TextModel has no undo stack, so `pushStackElement()` is the
/// documented command-boundary N-A seam.
fn CodeEditorWidget::run_select_all_core_command(
  self : CodeEditorWidget,
  nominal_source~ : String = "",
) -> Bool {
  // ViewController `_selectAll` supplies `{source:'mouse'}` but the core body
  // intentionally ignores it and hard-codes `keyboard`.
  guard self.get_view_model() is Some(view_model) else { return false }
  editor_registry().run_core_editor_command(
    self,
    view_model,
    "editor.action.selectAll",
    args=BaseCommandArguments(CursorBaseCommandOptions(source=nominal_source)),
  )
}

///|
/// Applies `NavigationCommandRevealType` at the root browser seam. Regular and
/// Minimal are both only the source command's `None` gate: MoveTo/Word/Line all
/// call `revealAllCursors(..., minimalReveal=true, ScrollType.Smooth)` after
/// passing it. Word/MoveTo reveal horizontally; Line is vertical-only.
fn CodeEditorWidget::reveal_mouse_cursor(
  self : CodeEditorWidget,
  reveal_type : @controller.NavigationCommandRevealType,
  horizontal~ : Bool,
  source~ : String,
) -> Unit {
  if reveal_type is None {
    return
  }
  self.reveal_view_cursor(
    horizontal~,
    source~,
    minimal_reveal=true,
    scroll_type=Smooth,
  )
}

///|
/// Converts a view position to a model position through the active converter.
fn CodeEditorWidget::view_to_model(
  self : CodeEditorWidget,
  view_position : @base_common.Position,
) -> @base_common.Position {
  match self.get_view_model() {
    Some(view_model) =>
      view_model
      .coordinates_converter()
      .view_position_to_model_position(view_position)
    None => view_position
  }
}
