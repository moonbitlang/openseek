///|
/// Source-shaped readonly cursor movement primitives.
///
/// Ported from
/// `vscode/src/vs/editor/common/cursor/cursorMoveOperations.ts` at
/// checked-in source.
///
/// The scoped surface is ordinary LTR movement with sticky tab stops off.
/// Atomic soft-tab movement, visual RTL swapping, blank-line/buffer commands,
/// and sticky End remain the explicit deferrals recorded in
/// `viewer-cursor-input-events-parity.md`.
///
/// `CursorPosition` (`cursorMoveOperations.ts:14-26`).
priv struct CursorMovePosition {
  line_number : Int
  column : Int
  leftover_visible_columns : Int
}

///|
/// The two `ICursorSimpleModel` implementations used by the scoped source:
/// the text model for logical-line Home/End and the view model for wrapped
///
/// navigation (`cursorMoveCommands.ts:32-117,475-538`).
priv enum CursorMoveModel {
  Model(@model.TextModel)
  View(ViewModel)
}

///|
/// `ICursorSimpleModel.getLineCount` (`cursorCommon.ts:253-267`).
fn CursorMoveModel::get_line_count(self : CursorMoveModel) -> Int {
  match self {
    Model(model) => model.get_line_count()
    View(view_model) => view_model.line_count()
  }
}

///|
/// `ICursorSimpleModel.getLineContent` (`cursorCommon.ts:253-267`).
fn CursorMoveModel::get_line_content(
  self : CursorMoveModel,
  line_number : Int,
) -> String {
  match self {
    Model(model) => model.get_line_content(line_number)
    View(view_model) => view_model.get_line_content(line_number)
  }
}

///|
/// `ICursorSimpleModel.getLineMinColumn` (`cursorCommon.ts:253-267`).
fn CursorMoveModel::get_line_min_column(
  self : CursorMoveModel,
  line_number : Int,
) -> Int {
  match self {
    Model(model) => model.get_line_min_column(line_number)
    View(view_model) => view_model.get_line_min_column(line_number)
  }
}

///|
/// `ICursorSimpleModel.getLineMaxColumn` (`cursorCommon.ts:253-267`).
fn CursorMoveModel::get_line_max_column(
  self : CursorMoveModel,
  line_number : Int,
) -> Int {
  match self {
    Model(model) => model.get_line_max_column(line_number)
    View(view_model) => view_model.get_line_max_column(line_number)
  }
}

///|
/// `ICursorSimpleModel.getLineFirstNonWhitespaceColumn` plus
/// `ViewModel.getLineFirstNonWhitespaceColumn`
///
/// (`cursorCommon.ts:258`, `viewModelImpl.ts:828-834`).
fn CursorMoveModel::get_line_first_non_whitespace_column(
  self : CursorMoveModel,
  line_number : Int,
) -> Int {
  match self {
    Model(model) => model.get_line_first_non_whitespace_column(line_number)
    View(view_model) => {
      let result = @base_common.first_non_whitespace_index(
        view_model.get_line_content(line_number),
      )
      if result == -1 {
        0
      } else {
        result + 1
      }
    }
  }
}

///|
/// `ICursorSimpleModel.getLineLastNonWhitespaceColumn`
/// (`cursorCommon.ts:259`) for both scoped model implementations.
fn CursorMoveModel::get_line_last_non_whitespace_column(
  self : CursorMoveModel,
  line_number : Int,
) -> Int {
  match self {
    Model(model) => model.get_line_last_non_whitespace_column(line_number)
    View(view_model) =>
      view_model.get_line_last_non_whitespace_column(line_number)
  }
}

///|
/// View-model side of `ICursorSimpleModel.getLineLastNonWhitespaceColumn`.
pub fn ViewModel::get_line_last_non_whitespace_column(
  self : ViewModel,
  line_number : Int,
) -> Int {
  let result = @base_common.last_non_whitespace_index(
    self.get_line_content(line_number),
  )
  if result == -1 {
    0
  } else {
    result + 2
  }
}

///|
/// Keep the complete scoped interface adapter in non-test builds.
let _cursor_move_last_non_whitespace_anchor : (CursorMoveModel, Int) -> Int = CursorMoveModel::get_line_last_non_whitespace_column

///|
/// `ICursorSimpleModel.normalizePosition` (`cursorCommon.ts:260`). The text
/// model has no injected-text ambiguity, so its implementation is the same
///
/// surrogate-validating clamp for every affinity.
fn CursorMoveModel::normalize_position(
  self : CursorMoveModel,
  position : @base_common.Position,
  affinity : @model.PositionAffinity,
) -> @base_common.Position {
  match self {
    Model(model) => model.validate_position(position)
    View(view_model) => view_model.normalize_position(position, affinity)
  }
}

///|
/// `CursorConfiguration.columnFromVisibleColumn`
///
/// (`cursorCommon.ts:233-247`), including its min/max clamps.
fn CursorMoveModel::column_from_visible_column(
  self : CursorMoveModel,
  line_number : Int,
  visible_column : Int,
  tab_size : Int,
) -> Int {
  let result = @core.column_from_visible_column(
    self.get_line_content(line_number),
    visible_column,
    tab_size,
  )
  let min_column = self.get_line_min_column(line_number)
  if result < min_column {
    return min_column
  }
  let max_column = self.get_line_max_column(line_number)
  if result > max_column {
    return max_column
  }
  result
}

///|
/// `strings.prevCharLength` at the exact offset consumed by
///
/// `MoveOperations.leftPosition` (`cursorMoveOperations.ts:29-39`).
fn cursor_prev_char_length(line_content : String, offset : Int) -> Int {
  if offset >= 2 &&
    @base_common.is_low_surrogate(line_content[offset - 1].to_int()) &&
    @base_common.is_high_surrogate(line_content[offset - 2].to_int()) {
    2
  } else {
    1
  }
}

///|
/// `strings.nextCharLength` at the exact offset consumed by
///
/// `MoveOperations.rightPosition` (`cursorMoveOperations.ts:110-118`).
fn cursor_next_char_length(line_content : String, offset : Int) -> Int {
  if offset + 1 < line_content.length() &&
    @base_common.is_high_surrogate(line_content[offset].to_int()) &&
    @base_common.is_low_surrogate(line_content[offset + 1].to_int()) {
    2
  } else {
    1
  }
}

///|
/// `MoveOperations.leftPosition` (`cursorMoveOperations.ts:29-39`).
fn cursor_left_position(
  model : CursorMoveModel,
  position : @base_common.Position,
) -> @base_common.Position {
  if position.column > model.get_line_min_column(position.line_number) {
    Position(
      position.line_number,
      position.column -
      cursor_prev_char_length(
        model.get_line_content(position.line_number),
        position.column - 1,
      ),
    )
  } else if position.line_number > 1 {
    let new_line_number = position.line_number - 1
    Position(new_line_number, model.get_line_max_column(new_line_number))
  } else {
    position
  }
}

///|
/// `MoveOperations.clipRange` (`cursorMoveOperations.ts:100-108`).
fn cursor_clip_range(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    return min
  }
  if value > max {
    return max
  }
  value
}

///|
/// `MoveOperations.clipPositionColumn` (`cursorMoveOperations.ts:91-98`).
fn cursor_clip_position_column(
  position : @base_common.Position,
  model : CursorMoveModel,
) -> @base_common.Position {
  Position(
    position.line_number,
    cursor_clip_range(
      position.column,
      model.get_line_min_column(position.line_number),
      model.get_line_max_column(position.line_number),
    ),
  )
}

///|
/// LTR, sticky-tab-false `MoveOperations.moveLeft`
///
/// (`cursorMoveOperations.ts:60-89`).
fn cursor_move_left(
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
  no_of_columns : Int,
) -> @cursor.SingleCursorState {
  let (line_number, column) = if cursor.has_selection() && !in_selection_mode {
    // Collapse to the beginning of the selection (`:68-72`).
    let selection = cursor.selection()
    (selection.start().line_number, selection.start().column)
  } else {
    // Pre-offset, clip before normalize(Left), then take one Unicode-scalar
    // step (`:73-82`). Atomic soft tabs are the recorded D2 deferral.
    let pos : @base_common.Position = Position(
      cursor.position.line_number,
      cursor.position.column - (no_of_columns - 1),
    )
    let normalized = model.normalize_position(
      cursor_clip_position_column(pos, model),
      Left,
    )
    let target = cursor_left_position(model, normalized)
    (target.line_number, target.column)
  }
  cursor.moved(
    in_selection_mode,
    Position(line_number, column),
    leftover_visible_columns=0,
  )
}

///|
/// `MoveOperations.rightPosition` (`cursorMoveOperations.ts:110-118`).
fn cursor_right_position(
  model : CursorMoveModel,
  line_number : Int,
  column : Int,
) -> @base_common.Position {
  let mut line_number = line_number
  let mut column = column
  if column < model.get_line_max_column(line_number) {
    column += cursor_next_char_length(
      model.get_line_content(line_number),
      column - 1,
    )
  } else if line_number < model.get_line_count() {
    line_number += 1
    column = model.get_line_min_column(line_number)
  }
  Position(line_number, column)
}

///|
/// LTR, sticky-tab-false `MoveOperations.moveRight`
///
/// (`cursorMoveOperations.ts:138-155`).
fn cursor_move_right(
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
  no_of_columns : Int,
) -> @cursor.SingleCursorState {
  let (line_number, column) = if cursor.has_selection() && !in_selection_mode {
    // Collapse to the end of the selection (`:142-146`).
    let selection = cursor.selection()
    (selection.end().line_number, selection.end().column)
  } else {
    // Pre-offset, clip before normalize(Right), then take one Unicode-scalar
    // step (`:147-153`). Atomic soft tabs are the recorded D2 deferral.
    let pos : @base_common.Position = Position(
      cursor.position.line_number,
      cursor.position.column + no_of_columns - 1,
    )
    let normalized = model.normalize_position(
      cursor_clip_position_column(pos, model),
      Right,
    )
    let target = cursor_right_position(
      model,
      normalized.line_number,
      normalized.column,
    )
    (target.line_number, target.column)
  }
  cursor.moved(
    in_selection_mode,
    Position(line_number, column),
    leftover_visible_columns=0,
  )
}

///|
/// `MoveOperations.vertical` (`cursorMoveOperations.ts:157-197`). Branch
/// order, edge handling, visible-column residue, and normalization adjustment
///
/// match the source.
fn cursor_vertical(
  tab_size : Int,
  model : CursorMoveModel,
  line_number : Int,
  column : Int,
  leftover_visible_columns : Int,
  new_line_number : Int,
  allow_move_on_edge_line : Bool,
  normalization_affinity? : @model.PositionAffinity,
) -> CursorMovePosition {
  let current_visible_column = @core.visible_column_from_column(
      model.get_line_content(line_number),
      column,
      tab_size,
    ) +
    leftover_visible_columns
  let line_count = model.get_line_count()
  let was_on_first_position = line_number == 1 && column == 1
  let was_on_last_position = line_number == line_count &&
    column == model.get_line_max_column(line_number)
  let was_at_edge_position = if new_line_number < line_number {
    was_on_first_position
  } else {
    was_on_last_position
  }
  let mut line_number = new_line_number
  let mut column = column
  if line_number < 1 {
    line_number = 1
    column = if allow_move_on_edge_line {
      model.get_line_min_column(line_number)
    } else {
      model.get_line_max_column(line_number).min(column)
    }
  } else if line_number > line_count {
    line_number = line_count
    column = if allow_move_on_edge_line {
      model.get_line_max_column(line_number)
    } else {
      model.get_line_max_column(line_number).min(column)
    }
  } else {
    column = model.column_from_visible_column(
      line_number, current_visible_column, tab_size,
    )
  }
  let mut leftover_visible_columns = if was_at_edge_position {
    0
  } else {
    current_visible_column -
    @core.visible_column_from_column(
      model.get_line_content(line_number),
      column,
      tab_size,
    )
  }
  if normalization_affinity is Some(affinity) {
    let new_position = model.normalize_position(
      Position(line_number, column),
      affinity,
    )
    leftover_visible_columns += column - new_position.column
    line_number = new_position.line_number
    column = new_position.column
  }
  { line_number, column, leftover_visible_columns, }
}

///|
/// `MoveOperations.down` (`cursorMoveOperations.ts:199-201`).
fn cursor_down(
  tab_size : Int,
  model : CursorMoveModel,
  line_number : Int,
  column : Int,
  leftover_visible_columns : Int,
  count : Int,
  allow_move_on_last_line : Bool,
) -> CursorMovePosition {
  cursor_vertical(
    tab_size,
    model,
    line_number,
    column,
    leftover_visible_columns,
    line_number + count,
    allow_move_on_last_line,
    normalization_affinity=RightOfInjectedText,
  )
}

///|
/// `MoveOperations.moveDown` (`cursorMoveOperations.ts:203-227`), including
///
/// the exact retry-normalization cap `i++ < 10`.
fn cursor_move_down_with_retry(
  line_number : Int,
  line_count : Int,
  step : (Int) -> (CursorMovePosition, Int),
) -> CursorMovePosition {
  for i = 0 {
    let (target, normalized_line_number) = step(i)
    if normalized_line_number > line_number {
      break target
    }
    if i < 10 && line_number + i + 1 < line_count {
      continue i + 1
    }
    break target
  }
}

///|
/// `MoveOperations.moveDown` (`cursorMoveOperations.ts:203-227`). The retry
/// controller above is extracted verbatim so the source's cap is directly
/// branch-testable without exposing a product debug API.
fn cursor_move_down(
  tab_size : Int,
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
  lines_count : Int,
) -> @cursor.SingleCursorState {
  let (line_number, column) = if cursor.has_selection() && !in_selection_mode {
    let selection = cursor.selection()
    (selection.end().line_number, selection.end().column)
  } else {
    (cursor.position.line_number, cursor.position.column)
  }
  let target = cursor_move_down_with_retry(
    line_number,
    model.get_line_count(),
    i => {
      let target = cursor_down(
        tab_size,
        model,
        line_number + i,
        column,
        cursor.leftover_visible_columns,
        lines_count,
        true,
      )
      let normalized = model.normalize_position(
        Position(target.line_number, target.column),
        None,
      )
      (target, normalized.line_number)
    },
  )
  cursor.moved(
    in_selection_mode,
    Position(target.line_number, target.column),
    leftover_visible_columns=target.leftover_visible_columns,
  )
}

///|
/// `MoveOperations.up` (`cursorMoveOperations.ts:242-246`).
fn cursor_up(
  tab_size : Int,
  model : CursorMoveModel,
  line_number : Int,
  column : Int,
  leftover_visible_columns : Int,
  count : Int,
  allow_move_on_first_line : Bool,
) -> CursorMovePosition {
  cursor_vertical(
    tab_size,
    model,
    line_number,
    column,
    leftover_visible_columns,
    line_number - count,
    allow_move_on_first_line,
    normalization_affinity=LeftOfInjectedText,
  )
}

///|
/// `MoveOperations.moveUp` (`cursorMoveOperations.ts:248-264`).
fn cursor_move_up(
  tab_size : Int,
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
  lines_count : Int,
) -> @cursor.SingleCursorState {
  let (line_number, column) = if cursor.has_selection() && !in_selection_mode {
    let selection = cursor.selection()
    (selection.start().line_number, selection.start().column)
  } else {
    (cursor.position.line_number, cursor.position.column)
  }
  let target = cursor_up(
    tab_size,
    model,
    line_number,
    column,
    cursor.leftover_visible_columns,
    lines_count,
    true,
  )
  cursor.moved(
    in_selection_mode,
    Position(target.line_number, target.column),
    leftover_visible_columns=target.leftover_visible_columns,
  )
}

///|
/// `MoveOperations.moveToBeginningOfLine`
/// (`cursorMoveOperations.ts:323-338`), including the whitespace-only `0`
///
/// sentinel and indentation toggle.
fn cursor_move_to_beginning_of_line(
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
) -> @cursor.SingleCursorState {
  let line_number = cursor.position.line_number
  let min_column = model.get_line_min_column(line_number)
  let candidate = model.get_line_first_non_whitespace_column(line_number)
  let first_non_blank_column = if candidate == 0 {
    min_column
  } else {
    candidate
  }
  let column = if cursor.position.column == first_non_blank_column {
    min_column
  } else {
    first_non_blank_column
  }
  cursor.moved(
    in_selection_mode,
    Position(line_number, column),
    leftover_visible_columns=0,
  )
}

///|
/// Sticky-false `MoveOperations.moveToEndOfLine`
/// (`cursorMoveOperations.ts:340-344`). The sticky-true large-leftover arm is
///
/// an approved deferral and is rejected by the command adapter.
fn cursor_move_to_end_of_line(
  model : CursorMoveModel,
  cursor : @cursor.SingleCursorState,
  in_selection_mode : Bool,
) -> @cursor.SingleCursorState {
  let line_number = cursor.position.line_number
  cursor.moved(
    in_selection_mode,
    Position(line_number, model.get_line_max_column(line_number)),
    leftover_visible_columns=0,
  )
}
