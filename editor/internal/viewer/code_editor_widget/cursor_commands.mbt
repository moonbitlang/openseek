// The readonly cursor-key subset of Monaco's `CoreNavigationCommands`
// (`coreCommands.ts:651-890,987-1163`) at
// checked-in source. The 16 required primary
// registrations deliberately come after contribution registrations; see
// `editor_extensions.mbt` for the local weight/context-expression seam.

///|
/// Runtime `Partial<MoveCommandOptions>` shape used by the private pointer
/// commands. The required TypeScript `position` is optional here because the
/// source command receives a `Partial` object and returns before doing cursor
/// work when it is absent. `view_position` is the optional already-known view
/// coordinate used by MoveTo/Line.
priv struct CursorMoveCommandArgs {
  source : String
  position : @base_common.Position?
  view_position : @base_common.Position?
  reveal_type : @controller.NavigationCommandRevealType
}

///|
fn CursorMoveCommandArgs::CursorMoveCommandArgs(
  source? : String = "",
  position? : @base_common.Position,
  view_position? : @base_common.Position,
  reveal_type? : @controller.NavigationCommandRevealType = Regular,
) -> CursorMoveCommandArgs {
  { source, position, view_position, reveal_type, }
}

///|
fn CursorMoveCommandArgs::empty() -> CursorMoveCommandArgs {
  CursorMoveCommandArgs()
}

///|
/// `BaseCommandOptions`: every core cursor command can retain a source.
priv struct CursorBaseCommandOptions {
  source : String
}

///|
fn CursorBaseCommandOptions::CursorBaseCommandOptions(
  source? : String = "keyboard",
) -> CursorBaseCommandOptions {
  { source, }
}

///|
/// `CursorMoveCommandOptions`: invocation-time source plus the optional page
/// size override consumed only by static `PAGE_SIZE_MARKER` commands.
priv struct CursorMoveCommandOptions {
  source : String
  page_size : Int?
}

///|
fn CursorMoveCommandOptions::CursorMoveCommandOptions(
  source? : String = "keyboard",
  page_size? : Int,
) -> CursorMoveCommandOptions {
  { source, page_size, }
}

///|
/// Exact optional `EndCommandOptions.sticky` contract.
priv struct EndCommandOptions {
  source : String
  sticky : Bool?
}

///|
fn EndCommandOptions::EndCommandOptions(
  source? : String = "keyboard",
  sticky? : Bool,
) -> EndCommandOptions {
  { source, sticky, }
}

///|
/// Source-shaped full `SetSelectionCommandOptions`: selection is required and
/// the base source is retained. The separate partial record below represents
/// what `CoreEditorCommand.runEditorCommand` can receive at runtime.
priv struct SetSelectionCommandOptions {
  source : String
  selection : @core.Selection
}

///|
fn SetSelectionCommandOptions::SetSelectionCommandOptions(
  selection : @core.Selection,
  source? : String = "",
) -> SetSelectionCommandOptions {
  { source, selection, }
}

///|
/// Runtime `Partial<SetSelectionCommandOptions>` shape.
priv struct CursorSetSelectionCommandArgs {
  source : String
  selection : @core.Selection?
}

///|
fn CursorSetSelectionCommandArgs::CursorSetSelectionCommandArgs(
  source? : String = "",
  selection? : @core.Selection,
) -> CursorSetSelectionCommandArgs {
  { source, selection, }
}

///|
fn CursorSetSelectionCommandArgs::from_options(
  options : SetSelectionCommandOptions,
) -> CursorSetSelectionCommandArgs {
  { source: options.source, selection: Some(options.selection), }
}

///|
/// Type-erased cursor command arguments stored by `CoreEditorCommand<T>`'s
/// local runtime representation.
priv enum CursorCoreCommandArgs {
  NoCursorCommandArguments
  BaseCommandArguments(CursorBaseCommandOptions)
  MoveCommandArguments(CursorMoveCommandArgs)
  SimpleMoveCommandArguments(CursorMoveCommandOptions)
  EndCommandArguments(EndCommandOptions)
  SetSelectionCommandArguments(CursorSetSelectionCommandArgs)
}

///|
/// `BaseMoveToCommand`: the constructor-owned field is used by both registered
/// `_moveTo` objects rather than passed as an incidental helper boolean.
priv struct BaseMoveToCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn BaseMoveToCommand::BaseMoveToCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> BaseMoveToCommand {
  { id, in_selection_mode, }
}

///|
fn BaseMoveToCommand::as_core_editor_command(
  self : BaseMoveToCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: MoveCommandArguments(CursorMoveCommandArgs::empty()),
    run_core_editor_command: (viewer, view_model, args) => {
      self.run(viewer, view_model, args)
    },
  }
}

///|
/// Source-shaped BaseMoveTo command body. The readonly TextModel owns no undo
/// stack, so the source's `pushStackElement()` has no local state to mutate;
/// all cursor work after that boundary is retained in source order.
fn BaseMoveToCommand::run(
  self : BaseMoveToCommand,
  viewer : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  core_args : CursorCoreCommandArgs,
) -> Bool {
  let args = match core_args {
    MoveCommandArguments(args) => args
    _ => CursorMoveCommandArgs::empty()
  }
  guard args.position is Some(position) else { return false }
  let changed = view_model.move_cursor_to_model_position(
    position,
    self.in_selection_mode,
    view_position?=args.view_position,
    source=args.source,
    reason=Explicit,
  )
  if changed && args.reveal_type != None {
    viewer.reveal_mouse_cursor(
      args.reveal_type,
      horizontal=true,
      source=args.source,
    )
  }
  changed
}

///|
/// `CursorMoveBasedCommand` retains one exact `SimpleMoveArguments` object.
priv struct CursorMoveBasedCommand {
  id : String
  static_args : @view_model.SimpleMoveArguments
}

///|
fn CursorMoveBasedCommand::CursorMoveBasedCommand(
  id : String,
  args : @view_model.SimpleMoveArguments,
) -> CursorMoveBasedCommand {
  { id, static_args: args, }
}

///|
fn CursorMoveBasedCommand::as_core_editor_command(
  self : CursorMoveBasedCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: SimpleMoveCommandArguments(CursorMoveCommandOptions()),
    run_core_editor_command: (viewer, view_model, args) => {
      self.run(viewer, view_model, args)
    },
  }
}

///|
fn CursorMoveBasedCommand::run(
  self : CursorMoveBasedCommand,
  viewer : CodeEditorWidget,
  _ : @view_model.ViewModel,
  core_args : CursorCoreCommandArgs,
) -> Bool {
  let dynamic_args = match core_args {
    SimpleMoveCommandArguments(args) => args
    _ => CursorMoveCommandOptions()
  }
  if self.static_args.value == -1 {
    let page_size = dynamic_args.page_size.unwrap_or(-1)
    viewer.run_cursor_page(
      self.static_args.direction,
      self.static_args.select,
      page_size~,
      source=dynamic_args.source,
    )
  } else {
    viewer.run_cursor_move(
      self.static_args.direction,
      self.static_args.select,
      value=self.static_args.value,
      unit=self.static_args.unit,
      source=dynamic_args.source,
    )
  }
}

///|
priv struct HomeCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn HomeCommand::HomeCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> HomeCommand {
  { id, in_selection_mode, }
}

///|
fn HomeCommand::as_core_editor_command(self : HomeCommand) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: BaseCommandArguments(CursorBaseCommandOptions()),
    run_core_editor_command: (viewer, view_model, args) => {
      let options = match args {
        BaseCommandArguments(options) => options
        _ => CursorBaseCommandOptions()
      }
      ignore(view_model)
      viewer.run_cursor_home(self.in_selection_mode, source=options.source)
    },
  }
}

///|
/// Unbound model-line-start command retained for the source's macOS-only
/// `cursorLineStart` registrations. The keybindings remain explicitly
/// deferred, but the command object and body are live and source-addressable.
priv struct LineStartCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn LineStartCommand::LineStartCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> LineStartCommand {
  { id, in_selection_mode, }
}

///|
fn LineStartCommand::exec(
  self : LineStartCommand,
  state : @cursor.SingleCursorState,
) -> @cursor.SingleCursorState {
  state.moved(
    self.in_selection_mode,
    Position(state.position.line_number, 1),
    leftover_visible_columns=0,
  )
}

///|
fn LineStartCommand::as_core_editor_command(
  self : LineStartCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: BaseCommandArguments(CursorBaseCommandOptions()),
    run_core_editor_command: (viewer, view_model, args) => {
      let options = match args {
        BaseCommandArguments(options) => options
        _ => CursorBaseCommandOptions()
      }
      let changed = view_model.set_cursor_state(
        Some(
          @cursor.CursorState::from_model_state(
            self.exec(view_model.cursor.model_state()),
          ),
        ),
        options.source,
        Explicit,
      )
      viewer.reveal_cursor_after_navigation(options.source)
      changed
    },
  }
}

///|
priv struct EndCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn EndCommand::EndCommand(id : String, in_selection_mode~ : Bool) -> EndCommand {
  { id, in_selection_mode, }
}

///|
fn EndCommand::as_core_editor_command(self : EndCommand) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: EndCommandArguments(EndCommandOptions(sticky=false)),
    run_core_editor_command: (viewer, view_model, args) => {
      let options = match args {
        EndCommandArguments(options) => options
        _ => EndCommandOptions()
      }
      let sticky = options.sticky.unwrap_or(false)
      ignore(view_model)
      viewer.run_cursor_end(
        self.in_selection_mode,
        sticky~,
        source=options.source,
      )
    },
  }
}

///|
/// Unbound model-line-end counterpart of `LineStartCommand`.
priv struct LineEndCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn LineEndCommand::LineEndCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> LineEndCommand {
  { id, in_selection_mode, }
}

///|
fn LineEndCommand::exec(
  self : LineEndCommand,
  view_model : @view_model.ViewModel,
  state : @cursor.SingleCursorState,
) -> @cursor.SingleCursorState {
  let line_number = state.position.line_number
  state.moved(
    self.in_selection_mode,
    Position(line_number, view_model.model_line_max_column(line_number)),
    leftover_visible_columns=0,
  )
}

///|
fn LineEndCommand::as_core_editor_command(
  self : LineEndCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: BaseCommandArguments(CursorBaseCommandOptions()),
    run_core_editor_command: (viewer, view_model, args) => {
      let options = match args {
        BaseCommandArguments(options) => options
        _ => CursorBaseCommandOptions()
      }
      let changed = view_model.set_cursor_state(
        Some(
          @cursor.CursorState::from_model_state(
            self.exec(view_model, view_model.cursor.model_state()),
          ),
        ),
        options.source,
        Explicit,
      )
      viewer.reveal_cursor_after_navigation(options.source)
      changed
    },
  }
}

///|
priv struct WordCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn WordCommand::WordCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> WordCommand {
  { id, in_selection_mode, }
}

///|
fn WordCommand::as_core_editor_command(self : WordCommand) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: MoveCommandArguments(CursorMoveCommandArgs::empty()),
    run_core_editor_command: (viewer, view_model, args) => {
      let args = match args {
        MoveCommandArguments(args) => args
        _ => CursorMoveCommandArgs::empty()
      }
      guard args.position is Some(position) else { return false }
      let changed = view_model.move_cursor_word(
        position,
        self.in_selection_mode,
        source=args.source,
        reason=Explicit,
      )
      if args.reveal_type != None {
        viewer.reveal_mouse_cursor(
          args.reveal_type,
          horizontal=true,
          source=args.source,
        )
      }
      changed
    },
  }
}

///|
priv struct LineCommand {
  id : String
  in_selection_mode : Bool
}

///|
fn LineCommand::LineCommand(
  id : String,
  in_selection_mode~ : Bool,
) -> LineCommand {
  { id, in_selection_mode, }
}

///|
fn LineCommand::as_core_editor_command(self : LineCommand) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: MoveCommandArguments(CursorMoveCommandArgs::empty()),
    run_core_editor_command: (viewer, view_model, args) => {
      let args = match args {
        MoveCommandArguments(args) => args
        _ => CursorMoveCommandArgs::empty()
      }
      guard args.position is Some(position) else { return false }
      let changed = view_model.move_cursor_line(
        position,
        self.in_selection_mode,
        view_position?=args.view_position,
        source=args.source,
        reason=Explicit,
      )
      if args.reveal_type != None {
        viewer.reveal_mouse_cursor(
          args.reveal_type,
          horizontal=false,
          source=args.source,
        )
      }
      changed
    },
  }
}

///|
/// The editor half of the source's anonymous editor/native SelectAll command.
priv struct SelectAllCommand {
  id : String
}

///|
fn SelectAllCommand::SelectAllCommand() -> SelectAllCommand {
  { id: "editor.action.selectAll", }
}

///|
fn SelectAllCommand::as_core_editor_command(
  self : SelectAllCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: NoCursorCommandArguments,
    run_core_editor_command: (viewer, view_model, _) => {
      guard viewer.get_model() is Some(model) else { return false }
      let snapshot = model.snapshot
      let last_line = snapshot.line_count() - 1
      let end = @base_common.Position(
        last_line + 1,
        snapshot.line_text(last_line).length() + 1,
      )
      let origin = @base_common.Position(1, 1)
      view_model.set_cursor_state(
        Some(
          @cursor.CursorState::from_model_state(
            SingleCursorState(origin, origin, Simple, end),
          ),
        ),
        "keyboard",
        Explicit,
      )
    },
  }
}

///|
/// The anonymous registered `SetSelection` command object.
priv struct SetSelectionCommand {
  id : String
}

///|
fn SetSelectionCommand::SetSelectionCommand() -> SetSelectionCommand {
  { id: "setSelection", }
}

///|
fn SetSelectionCommand::as_core_editor_command(
  self : SetSelectionCommand,
) -> CoreEditorCommand {
  {
    id: self.id,
    precondition: None,
    default_args: SetSelectionCommandArguments(CursorSetSelectionCommandArgs()),
    run_core_editor_command: (_, view_model, core_args) => {
      let args = match core_args {
        SetSelectionCommandArguments(args) => args
        _ => CursorSetSelectionCommandArgs()
      }
      guard args.selection is Some(selection) else { return false }
      view_model.set_cursor_state(
        Some(@cursor.CursorState::from_model_selection(selection)),
        args.source,
        Explicit,
      )
    },
  }
}

///|
fn CodeEditorWidget::run_move_to_core_command(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  args : CursorMoveCommandArgs?,
  in_selection_mode : Bool,
) -> Bool {
  let id = if in_selection_mode { "_moveToSelect" } else { "_moveTo" }
  editor_registry().run_core_editor_command(
    self,
    view_model,
    id,
    args?=args.map(value => MoveCommandArguments(value)),
  )
}

///|
fn CodeEditorWidget::run_word_core_command(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  args : CursorMoveCommandArgs?,
  in_selection_mode : Bool,
) -> Bool {
  let id = if in_selection_mode { "_wordSelectDrag" } else { "_wordSelect" }
  editor_registry().run_core_editor_command(
    self,
    view_model,
    id,
    args?=args.map(value => MoveCommandArguments(value)),
  )
}

///|
fn CodeEditorWidget::run_line_core_command(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  args : CursorMoveCommandArgs?,
  in_selection_mode : Bool,
) -> Bool {
  let id = if in_selection_mode { "_lineSelectDrag" } else { "_lineSelect" }
  editor_registry().run_core_editor_command(
    self,
    view_model,
    id,
    args?=args.map(value => MoveCommandArguments(value)),
  )
}

///|
fn CodeEditorWidget::run_set_selection_core_command(
  self : CodeEditorWidget,
  args : CursorSetSelectionCommandArgs?,
) -> Bool {
  guard self.get_view_model() is Some(view_model) else { return false }
  editor_registry().run_core_editor_command(
    self,
    view_model,
    "setSelection",
    args?=args.map(value => SetSelectionCommandArguments(value)),
  )
}

///|
/// ViewController's programmatic setSelection adapter: source is exactly
/// `keyboard` (`viewController.ts:94-99`).
fn CodeEditorWidget::set_selection_from_view_controller(
  self : CodeEditorWidget,
  selection : @core.Selection,
) -> Bool {
  let options = SetSelectionCommandOptions::SetSelectionCommandOptions(
    selection,
    source="keyboard",
  )
  self.run_set_selection_core_command(
    Some(CursorSetSelectionCommandArgs::from_options(options)),
  )
}

///|
/// ViewController's `_select` adapter: source is exactly `mouse`
/// (`viewController.ts:384-386`).
fn CodeEditorWidget::select_from_view_controller(
  self : CodeEditorWidget,
  selection : @core.Selection,
) -> Bool {
  let options = SetSelectionCommandOptions::SetSelectionCommandOptions(
    selection,
    source="mouse",
  )
  self.run_set_selection_core_command(
    Some(CursorSetSelectionCommandArgs::from_options(options)),
  )
}

///|
/// Keep the two exact source controller adapters in non-white-box builds.
/// Their current live pointer paths reach the same registered SetSelection
/// command through MoveTo/Word/Line, while the adapters remain part of the
/// source-shaped ViewController command surface.
let _view_controller_set_selection_anchor : (CodeEditorWidget, @core.Selection) -> Bool = CodeEditorWidget::set_selection_from_view_controller

///|
let _view_controller_select_anchor : (CodeEditorWidget, @core.Selection) -> Bool = CodeEditorWidget::select_from_view_controller

///|
/// Registers Left/Right/Up/Down/PageUp/PageDown/Home/End, each crossed with
/// Shift. Alternate platform chords and command metadata are deferred by the
/// approved parity ledger.
fn register_cursor_navigation_commands(
  registry : EditorContributionRegistry,
) -> Unit {
  register_unbound_cursor_core_command(
    registry,
    BaseMoveToCommand::BaseMoveToCommand("_moveTo", in_selection_mode=false).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    BaseMoveToCommand::BaseMoveToCommand(
      "_moveToSelect",
      in_selection_mode=true,
    ).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    WordCommand::WordCommand("_wordSelect", in_selection_mode=false).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    WordCommand::WordCommand("_wordSelectDrag", in_selection_mode=true).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineCommand::LineCommand("_lineSelect", in_selection_mode=false).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineCommand::LineCommand("_lineSelectDrag", in_selection_mode=true).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    SelectAllCommand::SelectAllCommand().as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    SetSelectionCommand::SetSelectionCommand().as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineStartCommand::LineStartCommand(
      "cursorLineStart",
      in_selection_mode=false,
    ).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineStartCommand::LineStartCommand(
      "cursorLineStartSelect",
      in_selection_mode=true,
    ).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineEndCommand::LineEndCommand("cursorLineEnd", in_selection_mode=false).as_core_editor_command(),
  )
  register_unbound_cursor_core_command(
    registry,
    LineEndCommand::LineEndCommand(
      "cursorLineEndSelect",
      in_selection_mode=true,
    ).as_core_editor_command(),
  )
  register_cursor_move_key_pair(
    registry,
    "cursorLeft",
    "ArrowLeft",
    Left,
    None,
    1,
  )
  register_cursor_move_key_pair(
    registry,
    "cursorRight",
    "ArrowRight",
    Right,
    None,
    1,
  )
  register_cursor_move_key_pair(
    registry,
    "cursorUp",
    "ArrowUp",
    Up,
    WrappedLine,
    1,
  )
  register_cursor_move_key_pair(
    registry,
    "cursorPageUp",
    "PageUp",
    Up,
    WrappedLine,
    -1,
  )
  register_cursor_move_key_pair(
    registry,
    "cursorDown",
    "ArrowDown",
    Down,
    WrappedLine,
    1,
  )
  register_cursor_move_key_pair(
    registry,
    "cursorPageDown",
    "PageDown",
    Down,
    WrappedLine,
    -1,
  )
  register_cursor_key_command(
    registry,
    HomeCommand::HomeCommand("cursorHome", in_selection_mode=false).as_core_editor_command(),
    "Home",
    shift=false,
  )
  register_cursor_key_command(
    registry,
    HomeCommand::HomeCommand("cursorHomeSelect", in_selection_mode=true).as_core_editor_command(),
    "Home",
    shift=true,
  )
  register_cursor_key_command(
    registry,
    EndCommand::EndCommand("cursorEnd", in_selection_mode=false).as_core_editor_command(),
    "End",
    shift=false,
  )
  register_cursor_key_command(
    registry,
    EndCommand::EndCommand("cursorEndSelect", in_selection_mode=true).as_core_editor_command(),
    "End",
    shift=true,
  )
}

///|
fn register_unbound_cursor_core_command(
  registry : EditorContributionRegistry,
  command : CoreEditorCommand,
) -> Unit {
  registry.register_core_editor_command(command, _ => true, [])
}

///|
/// Adds one exact primary rule. A model is the source command precondition;
/// once it passes, the registry reports handled independently of whether the
/// cursor changed at a document boundary.
fn register_cursor_key_command(
  registry : EditorContributionRegistry,
  command : CoreEditorCommand,
  key : String,
  shift~ : Bool,
) -> Unit {
  let keybinding_when = (viewer : CodeEditorWidget) => {
    viewer.is_code_presentation() && viewer.get_view_model() is Some(_)
  }
  if shift {
    registry.register_core_editor_command(command, keybinding_when, [], shift_keybindings=[
      (key, false, false),
    ])
  } else {
    registry.register_core_editor_command(command, keybinding_when, [
      (key, false, false),
    ])
  }
}

///|
/// Registers one cursor-key pair: the plain command on the bare key and its
/// `…Select` twin on Shift, in that order.
fn register_cursor_move_key_pair(
  registry : EditorContributionRegistry,
  id : String,
  key : String,
  direction : @view_model.SimpleMoveDirection,
  unit : @view_model.CursorMoveUnit,
  value : Int,
) -> Unit {
  register_cursor_key_command(
    registry,
    CursorMoveBasedCommand::CursorMoveBasedCommand(
      id,
      SimpleMoveArguments(direction, unit, false, value),
    ).as_core_editor_command(),
    key,
    shift=false,
  )
  register_cursor_key_command(
    registry,
    CursorMoveBasedCommand::CursorMoveBasedCommand(
      id + "Select",
      SimpleMoveArguments(direction, unit, true, value),
    ).as_core_editor_command(),
    key,
    shift=true,
  )
}

///|
/// Runs one character/wrapped-line command and always reveals after a winning
/// registration, even when the movement is a hard-boundary no-op.
fn CodeEditorWidget::run_cursor_move(
  self : CodeEditorWidget,
  direction : @view_model.SimpleMoveDirection,
  in_selection_mode : Bool,
  value? : Int = 1,
  unit? : @view_model.CursorMoveUnit = None,
  source? : String = "keyboard",
) -> Bool {
  guard self.get_view_model() is Some(view_model) else { return false }
  let changed = view_model.move_cursor_with_arguments(
    SimpleMoveArguments(direction, unit, in_selection_mode, value),
    source~,
    reason=Explicit,
  )
  self.reveal_cursor_after_navigation(source)
  changed
}

///|
/// Runs PageUp/PageDown with the source's exact static `-1` page marker.
/// Omitted/static-marker and exact-zero values use the live configured page
/// size; a positive dynamic value overrides it.
fn CodeEditorWidget::run_cursor_page(
  self : CodeEditorWidget,
  direction : @view_model.SimpleMoveDirection,
  in_selection_mode : Bool,
  page_size? : Int = -1,
  source? : String = "keyboard",
) -> Bool {
  guard self.get_view_model() is Some(view_model) else { return false }
  let changed = view_model.move_cursor_page(
    direction,
    in_selection_mode,
    page_size~,
    source~,
    reason=Explicit,
  )
  self.reveal_cursor_after_navigation(source)
  changed
}

///|
fn CodeEditorWidget::run_cursor_home(
  self : CodeEditorWidget,
  in_selection_mode : Bool,
  source? : String = "keyboard",
) -> Bool {
  guard self.get_view_model() is Some(view_model) else { return false }
  let changed = view_model.move_cursor_to_line_start(
    in_selection_mode,
    source~,
    reason=Explicit,
  )
  self.reveal_cursor_after_navigation(source)
  changed
}

///|
fn CodeEditorWidget::run_cursor_end(
  self : CodeEditorWidget,
  in_selection_mode : Bool,
  sticky? : Bool = false,
  source? : String = "keyboard",
) -> Bool {
  guard self.get_view_model() is Some(view_model) else { return false }
  let changed = view_model.move_cursor_to_line_end(
    in_selection_mode,
    sticky~,
    source~,
    reason=Explicit,
  )
  self.reveal_cursor_after_navigation(source)
  changed
}

///|
fn CodeEditorWidget::reveal_cursor_after_navigation(
  self : CodeEditorWidget,
  source : String,
) -> Unit {
  self.reveal_view_cursor(
    horizontal=true,
    source~,
    minimal_reveal=false,
    scroll_type=Smooth,
  )
}
