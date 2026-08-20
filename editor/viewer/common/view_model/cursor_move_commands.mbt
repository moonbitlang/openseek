///|
/// Source-shaped command adapters for readonly cursor movement.
///
/// Ported from
/// `vscode/src/vs/editor/common/cursor/cursorMoveCommands.ts` and the scoped
/// Home/End/Page command callers in
/// `vscode/src/vs/editor/browser/coreCommands.ts`, pinned at
/// checked-in source.
/// Exact 15-member `CursorMove.Direction` enum contract
/// (`cursorMoveCommands.ts:929-948`). The viewport members remain behaviorally
/// deferred, but retaining them here keeps the aggregate source type complete.
pub(all) enum CursorMoveDirection {
  Left
  Right
  Up
  Down
  PrevBlankLine
  NextBlankLine
  WrappedLineStart
  WrappedLineFirstNonWhitespaceCharacter
  WrappedLineColumnCenter
  WrappedLineEnd
  WrappedLineLastNonWhitespaceCharacter
  ViewPortTop
  ViewPortCenter
  ViewPortBottom
  ViewPortIfOutside
} derive(Eq, Debug)

///|
/// MoonBit representation of the source's exact 11-member
/// `SimpleMoveDirection` union (`cursorMoveCommands.ts:950-962`).
pub(all) enum SimpleMoveDirection {
  Left
  Right
  Up
  Down
  PrevBlankLine
  NextBlankLine
  WrappedLineStart
  WrappedLineFirstNonWhitespaceCharacter
  WrappedLineColumnCenter
  WrappedLineEnd
  WrappedLineLastNonWhitespaceCharacter
} derive(Eq, Debug)

///|
/// Exact `CursorMove.Unit` enum contract (`cursorMoveCommands.ts:971-978`).
/// `None` and `WrappedLine` are behaviorally scoped; Line, Character,
/// HalfLine, and FoldedLine remain explicit branch deferrals.
pub(all) enum CursorMoveUnit {
  None
  Line
  WrappedLine
  Character
  HalfLine
  FoldedLine
} derive(Eq, Debug)

///|
/// Exact typed argument contract consumed by the bound simple-move commands.
pub struct SimpleMoveArguments {
  direction : SimpleMoveDirection
  unit : CursorMoveUnit
  select : Bool
  value : Int
} derive(Eq, Debug)

///|
pub fn SimpleMoveArguments::SimpleMoveArguments(
  direction : SimpleMoveDirection,
  unit : CursorMoveUnit,
  select : Bool,
  value : Int,
) -> SimpleMoveArguments {
  { direction, unit, select, value }
}

///|
/// Narrows the full Direction enum to the simple-move union. A viewport member
/// returns `None`, representing `simpleMove`'s runtime default/null arm under a
/// closed MoonBit type system.
pub fn CursorMoveDirection::as_simple(
  self : CursorMoveDirection,
) -> SimpleMoveDirection? {
  let result : SimpleMoveDirection? = match self {
    Left => Some(Left)
    Right => Some(Right)
    Up => Some(Up)
    Down => Some(Down)
    PrevBlankLine => Some(PrevBlankLine)
    NextBlankLine => Some(NextBlankLine)
    WrappedLineStart => Some(WrappedLineStart)
    WrappedLineFirstNonWhitespaceCharacter =>
      Some(WrappedLineFirstNonWhitespaceCharacter)
    WrappedLineColumnCenter => Some(WrappedLineColumnCenter)
    WrappedLineEnd => Some(WrappedLineEnd)
    WrappedLineLastNonWhitespaceCharacter =>
      Some(WrappedLineLastNonWhitespaceCharacter)
    ViewPortTop | ViewPortCenter | ViewPortBottom | ViewPortIfOutside => None
  }
  result
}

///|
/// Whether a source-shaped command produced a model-side or view-side partial
///
/// cursor state (`PartialCursorState`, `cursorCommon.ts:269-328`).
priv enum CursorMoveResult {
  ByModel(@cursor.SingleCursorState)
  ByView(@cursor.SingleCursorState)
}

///|
/// Applies a partial cursor state through the one transition/emission spine.
fn ViewModel::commit_cursor_move(
  self : ViewModel,
  result : CursorMoveResult,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> Bool {
  match result {
    ByModel(state) => self.set_model_cursor_state(state, source, reason)
    ByView(state) => self.set_view_cursor_state(state, source, reason)
  }
}

///|
/// Clamps a raw view line/column before `coordinatesConverter.validateViewPosition`.
/// It deliberately does not normalize injected-text interiors or surrogate
/// boundaries: after the model-mapping check, `Cursor._validateViewState` owns
/// that normalization and adds the exact original-column correction to the
/// leftover-visible-column residue.
fn ViewModel::validate_cursor_move_view_position(
  self : ViewModel,
  position : @base_common.Position,
) -> @base_common.Position {
  let line_number = position.line_number.clamp(min=1, max=self.line_count())
  let min_column = self.get_line_min_column(line_number)
  let max_column = self.get_line_max_column(line_number)
  let column = position.column.clamp(min=min_column, max=max_column)
  Position(line_number, column)
}

///|
/// Resolves the paired model/view command arguments exactly like
/// `CursorMoveCommands.line`/`moveTo`: validate the required model position;
/// when a view position is supplied, retain it only if its normalized
/// view-to-model result equals that model position, otherwise fall back to a
/// model-to-view conversion. An absent view argument converts directly.
fn ViewModel::resolve_cursor_move_position(
  self : ViewModel,
  model_position : @base_common.Position,
  view_position : @base_common.Position?,
) -> (@base_common.Position, @base_common.Position) {
  let model_position = self.model.validate_position(model_position)
  let view_position = match view_position {
    None =>
      self.coordinates_converter.model_position_to_view_position(model_position)
    Some(view_position) => {
      let view_position = self.validate_cursor_move_view_position(view_position)
      let computed_model_position = self.model.validate_position(
        self.coordinates_converter.view_position_to_model_position(
          view_position,
        ),
      )
      if computed_model_position == model_position {
        view_position
      } else {
        self.coordinates_converter.model_position_to_view_position(
          model_position,
        )
      }
    }
  }
  (model_position, view_position)
}

///|
/// `CursorMoveCommands.simpleMove`'s approved LTR branches
/// (`cursorMoveCommands.ts:276-353,475-538`). A zero value follows the source
/// parser's `args.value || 1` fallback. Up/Down accept only WrappedLine;
/// logical/folded lines are approved deferrals. The return value reports a
/// changed state, not whether the winning keybinding was handled: the root
///
/// registry consumes a matched command even at a document boundary.
pub fn ViewModel::move_cursor(
  self : ViewModel,
  direction : SimpleMoveDirection,
  in_selection_mode : Bool,
  value? : Int = 1,
  unit? : CursorMoveUnit = None,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  self.move_cursor_with_arguments(
    SimpleMoveArguments(direction, unit, in_selection_mode, value),
    source~,
    reason~,
  )
}

///|
/// Full-Direction adapter that owns `simpleMove`'s runtime default/null arm.
/// The four viewport members are valid `Direction` values but not members of
/// the `SimpleMoveDirection` union, so they return without mutation here.
pub fn ViewModel::move_cursor_direction(
  self : ViewModel,
  direction : CursorMoveDirection,
  in_selection_mode : Bool,
  value? : Int = 1,
  unit? : CursorMoveUnit = None,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  guard direction.as_simple() is Some(simple_direction) else { return false }
  self.move_cursor(
    simple_direction,
    in_selection_mode,
    value~,
    unit~,
    source~,
    reason~,
  )
}

///|
/// Consumes the exact `SimpleMoveArguments` record retained by the bound
/// commands.
pub fn ViewModel::move_cursor_with_arguments(
  self : ViewModel,
  args : SimpleMoveArguments,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let direction = args.direction
  let unit = args.unit
  let in_selection_mode = args.select
  let value = if args.value == 0 { 1 } else { args.value }
  let state = self.cursor.get_primary_cursor_state()
  let model = CursorMoveModel::View(self)
  let result = match direction {
    Left => {
      guard unit != HalfLine else { return false }
      ByView(
        cursor_move_left(model, state.view_state, in_selection_mode, value),
      )
    }
    Right => {
      guard unit != HalfLine else { return false }
      ByView(
        cursor_move_right(model, state.view_state, in_selection_mode, value),
      )
    }
    Up => {
      guard unit == WrappedLine else { return false }
      ByView(
        cursor_move_up(
          self.options.tab_size,
          model,
          state.view_state,
          in_selection_mode,
          value,
        ),
      )
    }
    Down => {
      guard unit == WrappedLine else { return false }
      ByView(
        cursor_move_down(
          self.options.tab_size,
          model,
          state.view_state,
          in_selection_mode,
          value,
        ),
      )
    }
    PrevBlankLine
    | NextBlankLine
    | WrappedLineStart
    | WrappedLineFirstNonWhitespaceCharacter
    | WrappedLineColumnCenter
    | WrappedLineEnd
    | WrappedLineLastNonWhitespaceCharacter => return false
  }
  self.commit_cursor_move(result, source, reason)
}

///|
/// `CursorConfiguration.pageSize` (`cursorCommon.ts:129`): exactly
///
/// `max(1, floor(layoutHeight / lineHeight) - 2)`.
pub fn ViewModel::cursor_page_size(self : ViewModel) -> Int {
  ((self.view_layout.dimensions().height /
  self.view_layout.line_height().to_double())
  .floor()
  .to_int() -
  2).max(1)
}

///|
/// `CursorPageUp/Down`'s dynamic page argument (`coreCommands.ts:913-936`):
/// the static `PAGE_SIZE_MARKER = -1`, an omitted argument, or an exact-zero
/// dynamic override falls back to the live cursor page size; a positive
/// override is used unchanged. Movement is wrapped-view-line
///
/// `simpleMove`, not viewport scrolling.
pub fn ViewModel::move_cursor_page(
  self : ViewModel,
  direction : SimpleMoveDirection,
  in_selection_mode : Bool,
  page_size? : Int = 0,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  guard direction == Up || direction == Down else { return false }
  let value = if page_size == -1 || page_size == 0 {
    self.cursor_page_size()
  } else {
    page_size
  }
  self.move_cursor(
    direction,
    in_selection_mode,
    value~,
    unit=WrappedLine,
    source~,
    reason~,
  )
}

///|
/// `CursorMoveCommands._moveToLineStart`
/// (`cursorMoveCommands.ts:41-76`). The first wrapped segment uses logical
/// model indentation; a continuation that is not already at its own first
///
/// nonblank column uses view-line indentation.
pub fn ViewModel::move_cursor_to_line_start(
  self : ViewModel,
  in_selection_mode : Bool,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let cursor = self.cursor.get_primary_cursor_state()
  let current_view_column = cursor.view_state.position.column
  let current_model_column = cursor.model_state.position.column
  let is_first_line_of_wrapped_line = current_view_column ==
    current_model_column
  let current_view_line_number = cursor.view_state.position.line_number
  let view_model = CursorMoveModel::View(self)
  let first_non_blank_column = view_model.get_line_first_non_whitespace_column(
    current_view_line_number,
  )
  let is_beginning_of_view_line = current_view_column == first_non_blank_column
  let result = if !is_first_line_of_wrapped_line && !is_beginning_of_view_line {
    ByView(
      cursor_move_to_beginning_of_line(
        view_model,
        cursor.view_state,
        in_selection_mode,
      ),
    )
  } else {
    ByModel(
      cursor_move_to_beginning_of_line(
        Model(self.model),
        cursor.model_state,
        in_selection_mode,
      ),
    )
  }
  self.commit_cursor_move(result, source, reason)
}

///|
/// `CursorMoveCommands._moveToLineEnd`
/// (`cursorMoveCommands.ts:78-117`). `sticky=true` is deliberately rejected:
///
/// the large-leftover sticky arm is the approved CMO-059 deferral.
pub fn ViewModel::move_cursor_to_line_end(
  self : ViewModel,
  in_selection_mode : Bool,
  sticky? : Bool = false,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  guard !sticky else { return false }
  let cursor = self.cursor.get_primary_cursor_state()
  let view_position = cursor.view_state.position
  let view_max_column = self.get_line_max_column(view_position.line_number)
  let is_end_of_view_line = view_position.column == view_max_column
  let model_position = cursor.model_state.position
  let model_max_column = self.model.get_line_max_column(
    model_position.line_number,
  )
  let is_end_line_of_wrapped_line = view_max_column - view_position.column ==
    model_max_column - model_position.column
  let result = if is_end_of_view_line || is_end_line_of_wrapped_line {
    ByModel(
      cursor_move_to_end_of_line(
        Model(self.model),
        cursor.model_state,
        in_selection_mode,
      ),
    )
  } else {
    ByView(
      cursor_move_to_end_of_line(
        View(self),
        cursor.view_state,
        in_selection_mode,
      ),
    )
  }
  self.commit_cursor_move(result, source, reason)
}

///|
/// The current reduced `WordOperations.word` seam used by pointer
/// continuation. A model word uses `TextModel.get_word_at_position`; off a
/// word, the single UTF-16 code unit under the pointer is selected, matching
/// the existing readonly pointer behavior. Full token-aware WordOperations is
///
/// the approved D6 deferral.
fn ViewModel::cursor_word_move_result(
  self : ViewModel,
  cursor : @cursor.CursorState,
  in_selection_mode : Bool,
  model_position : @base_common.Position,
) -> CursorMoveResult {
  let (start_column, end_column) = match
    self.model.get_word_at_position(model_position) {
    Some(word) => (word.start_column, word.end_column)
    None => {
      let max_column = self.model.get_line_max_column(
        model_position.line_number,
      )
      (model_position.column, (model_position.column + 1).min(max_column))
    }
  }
  if !in_selection_mode {
    let anchor = @base_common.Position::Position(
      model_position.line_number,
      start_column,
    )
    let active = @base_common.Position::Position(
      model_position.line_number,
      end_column,
    )
    return ByModel(SingleCursorState(anchor, active, Word, active))
  }
  let anchor = cursor.model_state.selection_start_start
  let active : @base_common.Position = if model_position.line_number <
    anchor.line_number ||
    (
      model_position.line_number == anchor.line_number &&
      model_position.column < anchor.column
    ) {
    Position(model_position.line_number, start_column)
  } else {
    Position(model_position.line_number, end_column)
  }
  ByModel(cursor.model_state.moved(true, active))
}

///|
/// Reduced `CursorMoveCommands.word` command entry. The required model
/// position is validated before the selected-case readonly word seam runs;
/// complete token-aware `WordOperations` remains the approved CMC-033
/// deferral.
pub fn ViewModel::move_cursor_word(
  self : ViewModel,
  model_position : @base_common.Position,
  in_selection_mode : Bool,
  source? : String = "mouse",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let model_position = self.model.validate_position(model_position)
  let cursor = self.cursor.get_primary_cursor_state()
  self.commit_cursor_move(
    self.cursor_word_move_result(cursor, in_selection_mode, model_position),
    source,
    reason,
  )
}

///|
/// `CursorMoveCommands.line`'s continuing-selection branches
/// (`cursorMoveCommands.ts:179-230`). The supplied view position is retained
///
/// and never round-tripped through model coordinates.
fn ViewModel::cursor_line_move_result(
  self : ViewModel,
  cursor : @cursor.CursorState,
  model_position : @base_common.Position,
  view_position : @base_common.Position,
) -> CursorMoveResult {
  let entering_line_number = cursor.model_state.selection_start_start.line_number
  if model_position.line_number < entering_line_number {
    return ByView(
      cursor.view_state.moved(
        true,
        Position(view_position.line_number, 1),
        leftover_visible_columns=0,
      ),
    )
  }
  if model_position.line_number > entering_line_number {
    let line_count = self.line_count()
    let mut select_to_view_line_number = view_position.line_number + 1
    let mut select_to_view_column = 1
    if select_to_view_line_number > line_count {
      select_to_view_line_number = line_count
      select_to_view_column = self.get_line_max_column(
        select_to_view_line_number,
      )
    }
    return ByView(
      cursor.view_state.moved(
        true,
        Position(select_to_view_line_number, select_to_view_column),
        leftover_visible_columns=0,
      ),
    )
  }
  ByModel(
    cursor.model_state.moved(
      true,
      cursor.model_state.selection_start_end,
      leftover_visible_columns=0,
    ),
  )
}

///|
/// Source-shaped `CursorMoveCommands.line` entry. It accepts the required
/// model position plus the optional already-known view position, covering the
/// supplied/absent validation branches before either the new Line anchor or
/// the continuing-selection branches execute.
pub fn ViewModel::move_cursor_line(
  self : ViewModel,
  model_position : @base_common.Position,
  in_selection_mode : Bool,
  view_position? : @base_common.Position,
  source? : String = "mouse",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let (model_position, view_position) = self.resolve_cursor_move_position(
    model_position, view_position,
  )
  let cursor = self.cursor.get_primary_cursor_state()
  let result = if !in_selection_mode {
    let line_count = self.model.get_line_count()
    let mut select_to_line_number = model_position.line_number + 1
    let mut select_to_column = 1
    if select_to_line_number > line_count {
      select_to_line_number = line_count
      select_to_column = self.model.get_line_max_column(select_to_line_number)
    }
    let start = @base_common.Position::Position(model_position.line_number, 1)
    let active = @base_common.Position::Position(
      select_to_line_number, select_to_column,
    )
    ByModel(SingleCursorState(start, active, Line, active))
  } else {
    self.cursor_line_move_result(cursor, model_position, view_position)
  }
  self.commit_cursor_move(result, source, reason)
}

///|
/// `CoreNavigationCommands.LineSelectDrag` (`coreCommands.ts:1705-1730`)
/// always applies the Line continuation algorithm, even when Shift-gutter
/// begins from a Simple cursor. This dedicated entry therefore does not
/// dispatch on the stored anchor kind (unlike generic `move_cursor_to`). The
/// validated view position remains authoritative across wrapping and injected
/// text.
pub fn ViewModel::move_cursor_line_select_to(
  self : ViewModel,
  view_position : @base_common.Position,
  source? : String = "mouse",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let view_position = self.validate_cursor_move_view_position(view_position)
  let model_position = self.model.validate_position(
    self.coordinates_converter.view_position_to_model_position(view_position),
  )
  self.move_cursor_line(model_position, true, view_position~, source~, reason~)
}

///|
/// Source-shaped `CursorMoveCommands.moveTo` entry. The model position is
/// required and the already-known view position is optional, so tests and
/// root command adapters can exercise both source branches directly.
pub fn ViewModel::move_cursor_to_model_position(
  self : ViewModel,
  model_position : @base_common.Position,
  in_selection_mode : Bool,
  view_position? : @base_common.Position,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let cursor = self.cursor.get_primary_cursor_state()
  if in_selection_mode {
    match cursor.model_state.selection_start_kind {
      Word =>
        return self.move_cursor_word(model_position, true, source~, reason~)
      Line =>
        return self.move_cursor_line(
          model_position,
          true,
          view_position?,
          source~,
          reason~,
        )
      Simple => ()
    }
  }
  let (_, view_position) = self.resolve_cursor_move_position(
    model_position, view_position,
  )
  let result = ByView(
    cursor.view_state.moved(
      in_selection_mode,
      view_position,
      leftover_visible_columns=0,
    ),
  )
  self.commit_cursor_move(result, source, reason)
}

///|
/// `CursorMoveCommands.moveTo` (`cursorMoveCommands.ts:251-274`): continuing
/// Word/Line selections dispatch by the stored anchor kind before the Simple
/// view-side move. Model validation belongs to the shared controller seam;
///
/// the supplied view position remains authoritative under wrap/injected text.
pub fn ViewModel::move_cursor_to(
  self : ViewModel,
  view_position : @base_common.Position,
  in_selection_mode : Bool,
  source? : String = "keyboard",
  reason? : @editor_api.CursorChangeReason = Explicit,
) -> Bool {
  let view_position = self.validate_cursor_move_view_position(view_position)
  let model_position = self.model.validate_position(
    self.coordinates_converter.view_position_to_model_position(view_position),
  )
  self.move_cursor_to_model_position(
    model_position,
    in_selection_mode,
    view_position~,
    source~,
    reason~,
  )
}

///|
#deprecated
pub extend CursorMoveDirection with Debug::{to_repr}

///|
pub extend CursorMoveDirection with Eq::{equal, not_equal}

///|
#deprecated
pub extend CursorMoveUnit with Debug::{to_repr}

///|
pub extend CursorMoveUnit with Eq::{equal, not_equal}

///|
#deprecated
pub extend SimpleMoveArguments with Debug::{to_repr}

///|
pub extend SimpleMoveArguments with Eq::{equal, not_equal}

///|
#deprecated
pub extend SimpleMoveDirection with Debug::{to_repr}

///|
pub extend SimpleMoveDirection with Eq::{equal, not_equal}
