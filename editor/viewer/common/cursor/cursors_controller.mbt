///|
/// Owns the readonly editor's primary cursor and the single transition spine
/// shared by API, pointer, keyboard, and model-content changes. This is the
/// single-cursor reduction of Monaco's `CursorsController` plus
/// `CursorCollection`: every accepted transition commits a paired model/view
/// state and returns one fact for the ViewModel's outgoing dispatcher.
struct CursorsController {
  model : @model.TextModel
  mut known_model_version_id : Int32
  mut context : CursorContext
  mut cursor : Cursor
  mut is_handling : Bool
}

///|
/// Builds a controller at the document origin and captures the model's
/// internal content version, never its caller-owned host metadata version.
pub fn CursorsController::CursorsController(
  model : @model.TextModel,
  context : CursorContext,
) -> CursorsController {
  {
    model,
    known_model_version_id: model.get_version_id(),
    context,
    cursor: Cursor(),
    is_handling: false,
  }
}

///|
/// Installs a changed converter and reprojects only from the validated model
/// side. The source's simultaneous model/view cross-validation surface is an
/// approved deferral; this local reduced seam therefore emits no public model
/// cursor event.
pub fn CursorsController::set_context(
  self : CursorsController,
  context : CursorContext,
) -> Unit {
  self.context = context
  if self.known_model_version_id != self.model.get_version_id() {
    // The content event's second loop will recover/reset the cursor after the
    // view-model structural update finishes.
    return
  }
  if self.is_handling {
    // A nested injected-text/mapping notification is covered by the outer
    // reprojection, matching the source recursion guard.
    return
  }
  self.is_handling = true
  self.cursor.reproject(context)
  self.is_handling = false
}

///|
/// Returns the paired primary state.
pub fn CursorsController::get_primary_cursor_state(
  self : CursorsController,
) -> CursorState {
  self.cursor.as_cursor_state()
}

///|
/// The current model-coordinate state.
pub fn CursorsController::model_state(
  self : CursorsController,
) -> SingleCursorState {
  self.cursor.model_state
}

///|
/// The current view-coordinate state.
pub fn CursorsController::view_state(
  self : CursorsController,
) -> SingleCursorState {
  self.cursor.view_state
}

///|
/// Captures internal version and paired cursor state as one equality unit.
fn CursorsController::snapshot(self : CursorsController) -> CursorModelState {
  {
    model_version_id: self.model.get_version_id(),
    cursor_state: self.cursor.as_cursor_state(),
  }
}

///|
/// Validates a supplied model state. Leftover columns survive only when the
/// corresponding anchor range or active position survives validation exactly.
fn CursorsController::validate_model_state(
  self : CursorsController,
  state : SingleCursorState,
) -> SingleCursorState {
  let validated_range = self.model.validate_range(
    Range(
      state.selection_start_start.line_number,
      state.selection_start_start.column,
      state.selection_start_end.line_number,
      state.selection_start_end.column,
    ),
  )
  let validated_start = @base_common.Position(
    validated_range.start_line_number,
    validated_range.start_column,
  )
  let validated_end = @base_common.Position(
    validated_range.end_line_number,
    validated_range.end_column,
  )
  let anchor_unchanged = validated_start == state.selection_start_start &&
    validated_end == state.selection_start_end
  let validated_position = self.model.validate_position(state.position)
  SingleCursorState(
    validated_start,
    validated_end,
    state.selection_start_kind,
    validated_position,
    selection_start_leftover_visible_columns=if anchor_unchanged {
      state.selection_start_leftover_visible_columns
    } else {
      0
    },
    leftover_visible_columns=if validated_position == state.position {
      state.leftover_visible_columns
    } else {
      0
    },
  )
}

///|
/// `CursorCollection.normalize`'s exact primary-only branch. This controller's
/// representation contains one `cursor` rather than a cursor array, so the
/// source condition `cursors.length === 1` is a structural invariant and the
/// method returns before allocating or sorting any normalization workspace.
fn CursorsController::normalize(self : CursorsController) -> Unit {
  ignore(self)
  return
}

///|
/// Applies one source-shaped partial state and returns a change fact only when
/// the full paired state or internal version changed. `None` is the source's
/// both-sides-null early return. A full state follows the model-authoritative
/// reprojection seam documented by ONE-028; live callers otherwise provide
/// exactly one side.
pub fn CursorsController::set_cursor_state(
  self : CursorsController,
  state : PartialCursorState?,
  source~ : String = "keyboard",
  reason~ : @editor_api.CursorChangeReason = NotSet,
) -> CursorStateChange? {
  let state = match state {
    None => return None
    Some(state) => state
  }
  let old_state = self.snapshot()
  let supplied_model_state = state.model_state()
  let supplied_view_state = state.view_state()
  let validated_model_state = match supplied_model_state {
    Some(model_state) => Some(self.validate_model_state(model_state))
    None => None
  }
  let state_changed = self.cursor.set_state(
    self.context,
    validated_model_state,
    supplied_view_state,
  )
  self.normalize()
  if !state_changed {
    return None
  }
  if supplied_model_state is None {
    // The supplied view state is authoritative under wrap/injected text. The
    // converter derives its model side and the model validates that side, but
    // the approved reduced seam must not round-trip it back to a potentially
    // different view position. Source dual-side cross-validation remains the
    // explicit ONE-028 deferral.
    let derived_model_state = self.cursor.model_state
    let validated_model_state = self.validate_model_state(derived_model_state)
    // In the source's missing-model branch the view state's two residues are
    // retained after view->model conversion/validation; the zero-on-clamp rule
    // applies only when callers supplied a model state directly.
    self.cursor.model_state = {
      ..validated_model_state,
      selection_start_leftover_visible_columns: derived_model_state.selection_start_leftover_visible_columns,
      leftover_visible_columns: derived_model_state.leftover_visible_columns,
    }
  }
  self.finish_transition(Some(old_state), source, reason)
}

///|
/// Completes an accepted mutation. Full equality is the first gate; public
/// outgoing delivery is a second gate that ignores view-only reprojections.
fn CursorsController::finish_transition(
  self : CursorsController,
  old_state : CursorModelState?,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> CursorStateChange? {
  let new_state = self.snapshot()
  match old_state {
    Some(old) if old == new_state => return None
    _ => ()
  }
  let source = if source == "" { "keyboard" } else { source }
  let (old_selections, old_model_version_id, has_outgoing_event) = match
    old_state {
    None => (None, 0, true)
    Some(old) =>
      (
        Some([old.cursor_state.model_state.selection()]),
        old.model_version_id,
        old.cursor_state.model_state != new_state.cursor_state.model_state,
      )
  }
  Some({
    old_selections,
    selections: [new_state.cursor_state.model_state.selection()],
    old_model_version_id,
    model_version_id: new_state.model_version_id,
    source,
    reason,
    reached_max_cursor_count: false,
    has_outgoing_event,
  })
}

///|
/// Model-content transition. A flush updates the known internal version,
/// rebuilds the cursor at the origin, and deliberately compares against a null
/// old snapshot so it emits even when the visible cursor was already there.
pub fn CursorsController::on_model_content_changed(
  self : CursorsController,
  event : @model.InternalModelContentChangeEvent,
) -> CursorStateChange? {
  self.known_model_version_id = event.raw_content_changed_event.version_id
  if self.is_handling {
    return None
  }
  if !event.raw_content_changed_event.contains_event(Flush) {
    return None
  }
  self.cursor = Cursor()
  self.finish_transition(None, "model", ContentFlush)
}

///|
/// The selection in model coordinates.
pub fn CursorsController::get_model_selection(
  self : CursorsController,
) -> @core.Selection {
  self.cursor.model_state.selection()
}

///|
/// The selection in view coordinates.
pub fn CursorsController::get_view_selection(
  self : CursorsController,
) -> @core.Selection {
  self.cursor.view_state.selection()
}
