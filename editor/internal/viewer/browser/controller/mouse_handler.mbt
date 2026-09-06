// Ported from `vscode/src/vs/editor/browser/controller/mouseHandler.ts`
// (checked-in vscode submodule):
// `IPointerHandlerHelper`, `MouseHandler`, `MouseDownOperation` and
// `MouseDownState`. The handler registers its own DOM listeners through
// `EditorMouseEventFactory` on the view DOM node, exactly like the source —
// the root package only constructs it. The touch-scroll slice from
// `pointerHandler.ts`/`touch.ts` is installed by this handler; touch tap and
// pen-selection dispatch remain intentionally unported.
//
// Shape notes:
//   * Monaco's `MouseHandler` also holds a `ViewContext` (view model, view
//     layout, configuration) and a `ViewController` (dispatch + event
//     emission). The viewer has neither type; their reads/dispatches ride on
//     `PointerHandlerHelper` closures (grouped and marked in the struct).
//   * `onCursorStateChanged` kept `MouseDownOperation._currentSelection`
//     fresh; this port reads the selection lazily through the helper's
//     `get_current_selection` instead of tracking view events.
//
// Omissions:
//   * The raw `pointerup` compensation listener is kept alongside the
//     pointer-capturing global monitor (`mouseHandler.ts:126-133`).
//   * `_setupMouseWheelZoomListener` (mouseHandler.ts:140-199) — no
//     mouse-wheel zoom; the viewer's wheel path stays on the overflow guard
//     (scrollbar_input.mbt).
//   * `emitMouseWheel`.
//   * the drag-and-drop text-move branch (`isDragAndDrop`,
//     mouseHandler.ts:461-497) and `emitMouseDrop/DropCanceled` — readonly
//     viewer (`EditorOption.readOnly` is constant `true`, so the source's
//     gate never passes either).
//   * `onConfigurationChanged`/`onHeightChanged` (no layout-change view
//     event reaches the handler; a mid-drag layout change keeps monitoring).
//   * `selectOnLineNumbers` reads as the Monaco default `true` (option not
//     modeled).
//   * `getTargetAtClientPoint`'s multi-window `getWindow` indirection
//     (single window).

///|
/// `NavigationCommandRevealType` (`coreCommands.ts:353-367`).
pub(all) enum NavigationCommandRevealType {
  /// Do regular revealing.
  Regular
  /// Do only minimal revealing.
  Minimal
  /// Do not reveal the position.
  None
} derive(Eq, Debug)

///|
/// `IMouseDispatchData` (`viewController.ts:21-40`): the resolved pointer
/// intent the handler hands to the viewer's `ViewController.dispatchMouse`
/// analog. `position` is a 1-based **view** position (the view→model conversion
/// happens per cursor command, exactly like the source).
pub(all) struct MouseDispatchData {
  position : @base_common.Position
  /// Desired visual viewport column (`IMouseTarget.mouseColumn`).
  mouse_column : Int
  reveal_type : NavigationCommandRevealType
  started_on_line_numbers : Bool
  in_selection_mode : Bool
  mouse_down_count : Int
  alt_key : Bool
  ctrl_key : Bool
  meta_key : Bool
  shift_key : Bool
  left_button : Bool
  middle_button : Bool
  on_injected_text : Bool
}

///|
/// `IPointerHandlerHelper` (`mouseHandler.ts:28-57`), the closure-struct form
/// (Monaco's is the object literal `View._createPointerHandlerHelper`
/// builds). The root `viewer` package builds this one so the internal
/// controller does not import the facade or reach into root-owned Viewer state.
///
/// Grouped deviations, each marked below:
///   * Monaco's `MouseHandler` also holds a `ViewContext` (view model, view
///     layout, configuration options) and a `ViewController`. The viewer has
///     neither type; their reads/dispatches ride on this same struct.
///   * omissions: `viewLinesGpu`/`dispatchTextAreaEvent` (no GPU renderer, no
///     textarea part; `focus_text_area` focuses the root section, exactly
///     Monaco's behavior sans textarea).
pub(all) struct PointerHandlerHelper {
  // --- IPointerHandlerHelper members (mouseHandler.ts:29-56) ---
  view_dom_node : @rdom.Element
  lines_content_dom_node : @rdom.Element
  view_lines_dom_node : @rdom.Element
  focus_text_area : () -> Unit
  get_last_render_data : () -> PointerHandlerLastRenderData
  render_now : () -> Unit
  should_suppress_mouse_down_on_view_zone : (String) -> Bool
  get_position_from_dom_info : (@rdom.Element, Int) -> @base_common.Position?
  visible_range_for_position : (Int, Int) -> @view.HorizontalPosition?
  get_line_width : (Int) -> Double
  // --- ViewContext substitutes (deviation, see header) ---
  /// The attached view model; `None` while the viewer has no model (Monaco's
  /// pointer handler only exists while a view — and thus a model — does).
  view_model : () -> @view_model.ViewModel?
  get_layout_info : () -> @config.EditorLayoutInfo
  get_font_info : () -> @config.FontInfo
  /// The current view-space selection (`MouseDownOperation._currentSelection`
  /// via `onCursorStateChanged` in the source; read lazily here).
  get_current_selection : () -> @core.Selection?
  // --- ViewController substitutes (deviation, see header) ---
  dispatch_mouse : (MouseDispatchData) -> Unit
  /// Runs after hit testing but before `MouseDownOperation.start`. Returning
  /// true suppresses the ordinary selection dispatch for a resolved
  /// definition-link press while preserving focus and the public mouse event.
  before_mouse_down_selection : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Bool
  emit_mouse_down : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Unit
  emit_mouse_up : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Unit
  emit_mouse_move : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Unit
  emit_context_menu : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Unit
  emit_mouse_drag : (
    @editor_browser.EditorDomMouseEvent,
    @editor_browser.MouseTarget,
  ) -> Unit
  emit_mouse_leave : (@editor_browser.EditorDomMouseEvent) -> Unit
  // --- retained viewer scroll seams (scrollbar_input.mbt, no Monaco mirror) ---
  overflow_guard : @rdom.Element
  editor_scrollable : @scrollbar.ScrollableElementDom
  hover_scrollable : () -> @scrollbar.ScrollableElementDom?
  view_layout : () -> @view_layout.ViewLayout?
  schedule_render : () -> Unit
}

///|
/// `MouseHandler` (mouseHandler.ts:59-358). Also carries the viewer's
/// retained scrollbar-drag slot (scrollbar_input.mbt).
struct MouseHandler {
  view_helper : PointerHandlerHelper
  mouse_target_factory : MouseTargetFactory
  mouse_down_operation : MouseDownOperation
  scrollbar_drag_monitor : @base_browser.GlobalPointerMoveMonitor
  mut touch_scroll_gesture : TouchScrollGesture?
  mut last_mouse_leave_time : Double
  mut mouse_leave_monitor : @base_common.Disposable?
  listeners : Array[@base_common.Disposable]
  /// The active scrollbar-thumb drag (scrollbar_input.mbt).
  mut drag : @scrollbar.ScrollbarDrag?
  /// Gesture-level platform predicate installed by the host platform.
  scrollbar_drag_should_reset : (Double, Double) -> Bool
  mut disposed : Bool
}

///|
pub fn MouseHandler::MouseHandler(
  view_helper : PointerHandlerHelper,
) -> MouseHandler {
  let mouse_target_factory = MouseTargetFactory(view_helper)
  let handler : MouseHandler = {
    view_helper,
    mouse_target_factory,
    mouse_down_operation: MouseDownOperation(view_helper, mouse_target_factory),
    scrollbar_drag_monitor: GlobalPointerMoveMonitor(),
    touch_scroll_gesture: None,
    last_mouse_leave_time: -1.0,
    mouse_leave_monitor: None,
    listeners: [],
    drag: None,
    scrollbar_drag_should_reset: (initial, current) => {
      scrollbar_drag_should_reset(initial, current)
    },
    disposed: false,
  }
  let mouse_events = @editor_browser.EditorMouseEventFactory(
    view_helper.view_dom_node,
  )
  handler.listeners.push(
    mouse_events.on_mouse_move(view_helper.view_dom_node, e => {
      handler.on_mouse_move(e)

      // See https://github.com/microsoft/vscode/issues/138789
      // When moving the mouse really quickly, the browser sometimes forgets
      // to send us a `mouseleave` or `mouseout` event. We therefore install
      // here a global `mousemove` listener to manually recover if the mouse
      // goes outside the editor. As soon as the mouse leaves outside of the
      // editor, we remove this listener
      if handler.mouse_leave_monitor is None {
        let recover = (event : @rdom.Event) => {
          if event.to_mouse_event() is Some(mouse) &&
            !mouse_event_target_within(mouse, handler.view_helper.view_dom_node) {
            // went outside the editor!
            handler.on_mouse_leave(
              EditorDomMouseEvent(
                mouse,
                false,
                handler.view_helper.view_dom_node,
              ),
            )
          }
        }
        @rdom.document().add_event_listener("mousemove", recover)
        handler.mouse_leave_monitor = Some(
          @base_common.Disposable::from(() => {
            @rdom.document().remove_event_listener("mousemove", recover)
          }),
        )
      }
    }),
  )
  handler.listeners.push(
    mouse_events.on_mouse_up(view_helper.view_dom_node, e => {
      handler.on_mouse_up(e)
    }),
  )
  handler.listeners.push(
    mouse_events.on_context_menu(view_helper.view_dom_node, e => {
      handler.on_context_menu(e)
    }),
  )
  handler.listeners.push(
    mouse_events.on_mouse_leave(view_helper.view_dom_node, e => {
      handler.on_mouse_leave(e)
    }),
  )
  // PointerEvent.detail is always zero, so it cannot drive double/triple
  // click semantics. Capture only its id and reuse it in the following
  // mousedown, exactly like MouseHandler's EditorPointerEventFactory seam.
  let capture_pointer_id = Ref(0)
  handler.listeners.push(
    mouse_events.on_pointer_down(view_helper.view_dom_node, (_event, pointer_id) => {
      capture_pointer_id.val = pointer_id
    }),
  )
  // The `pointerup` listener registered by `GlobalEditorPointerMoveMonitor`
  // does not get invoked 100% of the times (mouseHandler.ts:126-133); this
  // compensation listener simply communicates it.
  let pointer_up = (_event : @rdom.Event) => {
    handler.mouse_down_operation.on_pointer_up()
  }
  view_helper.view_dom_node.add_event_listener("pointerup", pointer_up)
  handler.listeners.push(
    @base_common.Disposable::from(() => {
      view_helper.view_dom_node.remove_event_listener("pointerup", pointer_up)
    }),
  )
  handler.listeners.push(
    mouse_events.on_mouse_down(view_helper.view_dom_node, e => {
      handler.on_mouse_down(e, capture_pointer_id.val)
    }),
  )
  handler.install_touch_scroll_gesture()
  handler
}

///|
pub fn MouseHandler::dispose(self : MouseHandler) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.end_scrollable_drag()
  self.scrollbar_drag_monitor.dispose()
  if self.touch_scroll_gesture is Some(gesture) {
    gesture.dispose()
  }
  self.touch_scroll_gesture = None
  for listener in self.listeners {
    listener.dispose()
  }
  self.listeners.clear()
  if self.mouse_leave_monitor is Some(monitor) {
    monitor.dispose()
  }
  self.mouse_leave_monitor = None
  self.mouse_down_operation.dispose()
}

///|
/// Cancels an in-progress selection drag without a repaint, for viewer
/// lifecycle resets (model change/clear) — stops the down-operation monitor.
pub fn MouseHandler::cancel_selection(self : MouseHandler) -> Unit {
  self.mouse_down_operation.on_pointer_up()
}

///|
/// `_createMouseTarget` (mouseHandler.ts:244-256), sans the shadow-root
/// `elementsFromPoint` recovery (no shadow DOM).
fn MouseHandler::create_mouse_target(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
  test_event_target : Bool,
) -> @editor_browser.MouseTarget {
  self.mouse_target_factory.create_mouse_target(
    (self.view_helper.get_last_render_data)(),
    e.editor_pos(),
    e.pos,
    e.relative_pos(),
    if test_event_target {
      e.target
    } else {
      None
    },
  )
}

///|
/// `_onMouseMove` (mouseHandler.ts:269-289).
fn MouseHandler::on_mouse_move(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  let target_is_widget = self.mouse_target_factory.mouse_target_is_widget(e)
  if !target_is_widget {
    e.prevent_default()
  }
  if self.mouse_down_operation.is_active() {
    // In selection/drag operation
    return
  }
  let actual_mouse_move_time = e.timestamp
  if actual_mouse_move_time < self.last_mouse_leave_time {
    // Due to throttling, this event occurred before the mouse left the
    // editor, therefore ignore it.
    return
  }
  (self.view_helper.emit_mouse_move)(e, self.create_mouse_target(e, true))
}

///|
/// `_onMouseLeave` (mouseHandler.ts:291-301).
fn MouseHandler::on_mouse_leave(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  if self.mouse_leave_monitor is Some(monitor) {
    monitor.dispose()
  }
  self.mouse_leave_monitor = None
  self.last_mouse_leave_time = @base_browser.wall_clock_now_ms()
  (self.view_helper.emit_mouse_leave)(e)
}

///|
/// `_onMouseUp` (mouseHandler.ts:303-308).
fn MouseHandler::on_mouse_up(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  (self.view_helper.emit_mouse_up)(e, self.create_mouse_target(e, true))
}

///|
/// `_onContextMenu` (mouseHandler.ts:262-266). Policy such as target filtering,
/// cursor movement, and native-menu suppression belongs to the subscribing
/// context-menu contribution, not the input controller.
fn MouseHandler::on_context_menu(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  (self.view_helper.emit_context_menu)(e, self.create_mouse_target(e, true))
}

///|
/// Runs the content-target part of `_onMouseDown` through narrow callbacks so
/// the definition-link pre-selection seam can be tested independently from DOM
/// hit testing. The public mouse-down event is deliberately emitted after both
/// the suppressed and ordinary selection paths.
fn run_mouse_down_selection_contract(
  should_handle : Bool,
  target_is_content : Bool,
  before_mouse_down_selection : () -> Bool,
  focus : () -> Unit,
  start_selection : () -> Unit,
  handle_non_content_target : () -> Unit,
  emit_mouse_down : () -> Unit,
) -> Unit {
  if should_handle && target_is_content {
    let suppress_selection = before_mouse_down_selection()
    focus()
    if !suppress_selection {
      start_selection()
    }
  } else {
    handle_non_content_target()
  }
  emit_mouse_down()
}

///|
/// `_onMouseDown` (mouseHandler.ts:310-353). `selectOnLineNumbers` reads as
/// the Monaco default `true`; the pointer id travels with `EditorDomMouseEvent`
/// into `MouseDownOperation.start`.
fn MouseHandler::on_mouse_down(
  self : MouseHandler,
  e : @editor_browser.EditorDomMouseEvent,
  pointer_id : Int,
) -> Unit {
  let t = self.create_mouse_target(e, true)
  let target_type = t.type_()
  let target_is_content = target_type is ContentText ||
    target_type is ContentEmpty
  let target_is_gutter = target_type is GutterGlyphMargin ||
    target_type is GutterLineNumbers ||
    target_type is GutterLineDecorations
  let target_is_line_numbers = target_type is GutterLineNumbers
  let select_on_line_numbers = true
  let target_is_view_zone = target_type is ContentViewZone ||
    target_type is GutterViewZone
  let mut should_handle = e.left_button || e.middle_button
  if @base_common.is_macintosh && e.left_button && e.ctrl_key {
    should_handle = false
  }
  let focus = () => {
    e.prevent_default()
    (self.view_helper.focus_text_area)()
  }
  run_mouse_down_selection_contract(
    should_handle,
    target_is_content,
    () => (self.view_helper.before_mouse_down_selection)(e, t),
    focus,
    () => self.mouse_down_operation.start(target_type, e, pointer_id),
    () => {
      if should_handle && target_is_line_numbers && select_on_line_numbers {
        focus()
        self.mouse_down_operation.start(target_type, e, pointer_id)
      } else if target_is_gutter {
        // Do not steal focus
        e.prevent_default()
      } else if target_is_view_zone {
        match t {
          MouseTargetViewZone(detail~, ..) =>
            if should_handle &&
              (self.view_helper.should_suppress_mouse_down_on_view_zone)(
                detail.view_zone_id,
              ) {
              focus()
              self.mouse_down_operation.start(target_type, e, pointer_id)
              e.prevent_default()
            }
          _ => ()
        }
      }
    },
    () => (self.view_helper.emit_mouse_down)(e, t),
  )
}

///|
/// `MouseDownOperation` (mouseHandler.ts:360-656).
priv struct MouseDownOperation {
  view_helper : PointerHandlerHelper
  mouse_target_factory : MouseTargetFactory
  mouse_move_monitor : @editor_browser.GlobalEditorPointerMoveMonitor
  top_bottom_drag_scrolling : DragScrolling
  left_right_drag_scrolling : DragScrolling
  mouse_state : MouseDownState
  mut is_active_flag : Bool
}

///|
fn MouseDownOperation::MouseDownOperation(
  view_helper : PointerHandlerHelper,
  mouse_target_factory : MouseTargetFactory,
) -> MouseDownOperation {
  let operation : MouseDownOperation = {
    view_helper,
    mouse_target_factory,
    mouse_move_monitor: GlobalEditorPointerMoveMonitor(
      view_helper.view_dom_node,
    ),
    top_bottom_drag_scrolling: DragScrolling(
      TopBottom,
      view_helper,
      mouse_target_factory,
      (_position, _in_selection_mode, _reveal_type) => (),
    ),
    left_right_drag_scrolling: DragScrolling(
      LeftRight,
      view_helper,
      mouse_target_factory,
      (_position, _in_selection_mode, _reveal_type) => (),
    ),
    mouse_state: MouseDownState(),
    is_active_flag: false,
  }
  // The drag-scrolling dispatch closures need the operation itself; rebuild
  // them now that it exists (the source passes
  // `(position, inSelectionMode, revealType) => this._dispatchMouse(...)`
  // into the constructors directly).
  operation.top_bottom_drag_scrolling.set_dispatch((
    position,
    in_selection_mode,
    reveal_type,
  ) => operation.dispatch_mouse_target(position, in_selection_mode, reveal_type))
  operation.left_right_drag_scrolling.set_dispatch((
    position,
    in_selection_mode,
    reveal_type,
  ) => operation.dispatch_mouse_target(position, in_selection_mode, reveal_type))
  operation
}

///|
fn MouseDownOperation::dispose(self : MouseDownOperation) -> Unit {
  self.mouse_move_monitor.dispose()
  self.top_bottom_drag_scrolling.dispose()
  self.left_right_drag_scrolling.dispose()
}

///|
fn MouseDownOperation::is_active(self : MouseDownOperation) -> Bool {
  self.is_active_flag
}

///|
/// `_onMouseDownThenMove` (mouseHandler.ts:410-440), sans the drag-and-drop
/// branch (header).
fn MouseDownOperation::on_mouse_down_then_move(
  self : MouseDownOperation,
  e : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  self.mouse_state.set_modifiers(e)
  guard self.find_mouse_position(e, false) is Some(position) else {
    // Ignoring because position is unknown
    return
  }
  if position is MouseTargetOutsideEditor(outside_position~, ..) {
    if outside_position is Above || outside_position is Below {
      self.top_bottom_drag_scrolling.start(position, e)
      self.left_right_drag_scrolling.stop()
    } else {
      self.left_right_drag_scrolling.start(position, e)
      self.top_bottom_drag_scrolling.stop()
    }
  } else {
    self.top_bottom_drag_scrolling.stop()
    self.left_right_drag_scrolling.stop()
    self.dispatch_mouse_target(position, true, Minimal)
  }
}

///|
/// `start` (mouseHandler.ts:442-512), sans the drag-and-drop gate (header:
/// `readOnly` is constant `true`, so the source's gate never passes).
fn MouseDownOperation::start(
  self : MouseDownOperation,
  target_type : @editor_browser.MouseTargetType,
  e : @editor_browser.EditorDomMouseEvent,
  pointer_id : Int,
) -> Unit {
  self.mouse_state.set_started_on_line_numbers(target_type is GutterLineNumbers)
  self.mouse_state.set_start_buttons(e)
  self.mouse_state.set_modifiers(e)
  guard self.find_mouse_position(e, true) is Some(position) else {
    // Ignoring because position is unknown
    return
  }
  guard position.position() is Some(target_position) else { return }
  self.mouse_state.try_set_count(e.detail, target_position)

  // Overwrite the detail of the MouseEvent, as it will be sent out in an
  // event and contributions might rely on it.
  e.set_detail(self.mouse_state.count())
  self.dispatch_mouse_target(position, e.shift_key, Minimal)
  if !self.is_active_flag {
    self.is_active_flag = true
    self.mouse_move_monitor.start_monitoring(
      self.view_helper.view_lines_dom_node,
      pointer_id,
      e.buttons,
      moved => self.on_mouse_down_then_move(moved),
      _browser_event => self.stop(),
    )
  }
}

///|
fn MouseDownOperation::stop(self : MouseDownOperation) -> Unit {
  self.is_active_flag = false
  self.top_bottom_drag_scrolling.stop()
  self.left_right_drag_scrolling.stop()
}

///|
fn MouseDownOperation::on_pointer_up(self : MouseDownOperation) -> Unit {
  self.mouse_move_monitor.stop_monitoring()
}

///|
/// `_getPositionOutsideEditor` (mouseHandler.ts:532-593). The RTL arms read
/// LTR-only (mouse_target.mbt header); `contentRight` takes the
/// minimap-hidden branch (no minimap part).
fn MouseDownOperation::get_position_outside_editor(
  self : MouseDownOperation,
  e : @editor_browser.EditorDomMouseEvent,
) -> @editor_browser.MouseTarget? {
  let editor_content = e.editor_pos()
  guard (self.view_helper.view_model)() is Some(view_model) else { return None }
  let view_layout = view_model.view_layout
  let mouse_column = self.mouse_target_factory.get_mouse_column(
    e.relative_pos(),
  )
  if e.posy < editor_content.y {
    let outside_distance = editor_content.y - e.posy
    let scrolled_above = view_layout.get_current_scroll_top() - outside_distance
    let vertical_offset = scrolled_above.max(0.0)
    if hit_test_get_zone_at_coord(view_model, vertical_offset)
      is Some(view_zone_data) &&
      self.help_position_jump_over_view_zone(view_zone_data)
      is Some(new_position) {
      return Some(
        @editor_browser.MouseTarget::create_outside_editor(
          mouse_column,
          new_position,
          Above,
          outside_distance,
        ),
      )
    }
    let above_line_number = view_layout.line_at_vertical_offset(vertical_offset)
    return Some(
      @editor_browser.MouseTarget::create_outside_editor(
        mouse_column,
        Position(above_line_number, 1),
        Above,
        outside_distance,
      ),
    )
  }
  if e.posy > editor_content.y + editor_content.height {
    let outside_distance = e.posy - editor_content.y - editor_content.height
    let vertical_offset = view_layout.get_current_scroll_top() +
      e.relative_pos().y
    if hit_test_get_zone_at_coord(view_model, vertical_offset)
      is Some(view_zone_data) &&
      self.help_position_jump_over_view_zone(view_zone_data)
      is Some(new_position) {
      return Some(
        @editor_browser.MouseTarget::create_outside_editor(
          mouse_column,
          new_position,
          Below,
          outside_distance,
        ),
      )
    }
    let below_line_number = view_layout.line_at_vertical_offset(vertical_offset)
    return Some(
      @editor_browser.MouseTarget::create_outside_editor(
        mouse_column,
        Position(
          below_line_number,
          view_model.get_line_max_column(below_line_number),
        ),
        Below,
        outside_distance,
      ),
    )
  }
  let possible_line_number = view_layout.line_at_vertical_offset(
    view_layout.get_current_scroll_top() + e.relative_pos().y,
  )
  let layout_info = (self.view_helper.get_layout_info)()
  let x_left_boundary = layout_info.content_left
  if e.relative_pos().x <= x_left_boundary {
    let outside_distance = x_left_boundary - e.relative_pos().x
    return Some(
      @editor_browser.MouseTarget::create_outside_editor(
        mouse_column,
        Position(possible_line_number, 1),
        Left,
        outside_distance,
      ),
    )
  }
  let content_right = layout_info.width - layout_info.vertical_scrollbar_width
  let x_right_boundary = content_right
  if e.relative_pos().x >= x_right_boundary {
    let outside_distance = e.relative_pos().x - x_right_boundary
    return Some(
      @editor_browser.MouseTarget::create_outside_editor(
        mouse_column,
        Position(
          possible_line_number,
          view_model.get_line_max_column(possible_line_number),
        ),
        Right,
        outside_distance,
      ),
    )
  }
  None
}

///|
/// `_findMousePosition` (mouseHandler.ts:595-615).
fn MouseDownOperation::find_mouse_position(
  self : MouseDownOperation,
  e : @editor_browser.EditorDomMouseEvent,
  test_event_target : Bool,
) -> @editor_browser.MouseTarget? {
  if self.get_position_outside_editor(e) is Some(position_outside_editor) {
    return Some(position_outside_editor)
  }
  let t = self.mouse_target_factory.create_mouse_target(
    (self.view_helper.get_last_render_data)(),
    e.editor_pos(),
    e.pos,
    e.relative_pos(),
    if test_event_target {
      e.target
    } else {
      None
    },
  )
  guard t.position() is Some(_) else { return None }
  if t is MouseTargetViewZone(type_~, element~, mouse_column~, detail~, ..) &&
    self.help_position_jump_over_view_zone(detail) is Some(new_position) {
    return Some(
      @editor_browser.MouseTarget::create_view_zone(
        type_, element, mouse_column, new_position, detail,
      ),
    )
  }
  Some(t)
}

///|
/// `_helpPositionJumpOverViewZone` (mouseHandler.ts:617-631): force the
/// position on view zones to go above or below depending on where the
/// selection started from.
fn MouseDownOperation::help_position_jump_over_view_zone(
  self : MouseDownOperation,
  view_zone_data : @editor_browser.MouseTargetViewZoneData,
) -> @base_common.Position? {
  guard (self.view_helper.get_current_selection)() is Some(current_selection) else {
    return None
  }
  let selection_start = current_selection.get_selection_start()
  match (view_zone_data.position_before, view_zone_data.position_after) {
    (Some(position_before), Some(position_after)) =>
      if position_before.is_before(selection_start) {
        Some(position_before)
      } else {
        Some(position_after)
      }
    _ => None
  }
}

///|
/// `_dispatchMouse` (mouseHandler.ts:633-655).
fn MouseDownOperation::dispatch_mouse_target(
  self : MouseDownOperation,
  position : @editor_browser.MouseTarget,
  in_selection_mode : Bool,
  reveal_type : NavigationCommandRevealType,
) -> Unit {
  guard position.position() is Some(target_position) else { return }
  let on_injected_text = match position {
    MouseTargetContentText(detail~, ..) => detail.injected_text is Some(_)
    _ => false
  }
  (self.view_helper.dispatch_mouse)({
    position: target_position,
    mouse_column: position.mouse_column(),
    reveal_type,
    started_on_line_numbers: self.mouse_state.started_on_line_numbers(),
    in_selection_mode,
    mouse_down_count: self.mouse_state.count(),
    alt_key: self.mouse_state.alt_key(),
    ctrl_key: self.mouse_state.ctrl_key(),
    meta_key: self.mouse_state.meta_key(),
    shift_key: self.mouse_state.shift_key(),
    left_button: self.mouse_state.left_button(),
    middle_button: self.mouse_state.middle_button(),
    on_injected_text,
  })
}

///|
/// `MouseDownState` (mouseHandler.ts:658-749).
priv struct MouseDownState {
  mut alt_key_flag : Bool
  mut ctrl_key_flag : Bool
  mut meta_key_flag : Bool
  mut shift_key_flag : Bool
  mut left_button_flag : Bool
  mut middle_button_flag : Bool
  mut started_on_line_numbers_flag : Bool
  mut last_mouse_down_position : @base_common.Position?
  mut last_mouse_down_position_equal_count : Int
  mut last_mouse_down_count : Int
  mut last_set_mouse_down_count_time : Double
}

///|
/// `CLEAR_MOUSE_DOWN_COUNT_TIME` (mouseHandler.ts:660).
const CLEAR_MOUSE_DOWN_COUNT_TIME : Double = 400.0 // ms

///|
fn MouseDownState::MouseDownState() -> MouseDownState {
  {
    alt_key_flag: false,
    ctrl_key_flag: false,
    meta_key_flag: false,
    shift_key_flag: false,
    left_button_flag: false,
    middle_button_flag: false,
    started_on_line_numbers_flag: false,
    last_mouse_down_position: None,
    last_mouse_down_position_equal_count: 0,
    last_mouse_down_count: 0,
    last_set_mouse_down_count_time: 0.0,
  }
}

///|
fn MouseDownState::alt_key(self : MouseDownState) -> Bool {
  self.alt_key_flag
}

///|
fn MouseDownState::ctrl_key(self : MouseDownState) -> Bool {
  self.ctrl_key_flag
}

///|
fn MouseDownState::meta_key(self : MouseDownState) -> Bool {
  self.meta_key_flag
}

///|
fn MouseDownState::shift_key(self : MouseDownState) -> Bool {
  self.shift_key_flag
}

///|
fn MouseDownState::left_button(self : MouseDownState) -> Bool {
  self.left_button_flag
}

///|
fn MouseDownState::middle_button(self : MouseDownState) -> Bool {
  self.middle_button_flag
}

///|
fn MouseDownState::started_on_line_numbers(self : MouseDownState) -> Bool {
  self.started_on_line_numbers_flag
}

///|
fn MouseDownState::count(self : MouseDownState) -> Int {
  self.last_mouse_down_count
}

///|
fn MouseDownState::set_modifiers(
  self : MouseDownState,
  source : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  self.alt_key_flag = source.alt_key
  self.ctrl_key_flag = source.ctrl_key
  self.meta_key_flag = source.meta_key
  self.shift_key_flag = source.shift_key
}

///|
fn MouseDownState::set_start_buttons(
  self : MouseDownState,
  source : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  self.left_button_flag = source.left_button
  self.middle_button_flag = source.middle_button
}

///|
fn MouseDownState::set_started_on_line_numbers(
  self : MouseDownState,
  started_on_line_numbers : Bool,
) -> Unit {
  self.started_on_line_numbers_flag = started_on_line_numbers
}

///|
/// `trySetCount` (mouseHandler.ts:724-747). `now` is injectable for tests;
/// the source reads `new Date().getTime()`.
fn MouseDownState::try_set_count(
  self : MouseDownState,
  set_mouse_down_count : Int,
  new_mouse_down_position : @base_common.Position,
  now? : Double,
) -> Unit {
  let mut set_mouse_down_count = set_mouse_down_count
  // a. Invalidate multiple clicking if too much time has passed
  let current_time = match now {
    Some(now) => now
    None => @base_browser.wall_clock_now_ms()
  }
  if current_time - self.last_set_mouse_down_count_time >
    CLEAR_MOUSE_DOWN_COUNT_TIME {
    set_mouse_down_count = 1
  }
  self.last_set_mouse_down_count_time = current_time

  // b. Ensure that we don't jump from single click to triple click in one go
  if set_mouse_down_count > self.last_mouse_down_count + 1 {
    set_mouse_down_count = self.last_mouse_down_count + 1
  }

  // c. Invalidate multiple clicking if the logical position is different
  match self.last_mouse_down_position {
    Some(last) if last.equals(new_mouse_down_position) =>
      self.last_mouse_down_position_equal_count += 1
    _ => self.last_mouse_down_position_equal_count = 1
  }
  self.last_mouse_down_position = Some(new_mouse_down_position)

  // Finally set the lastMouseDownCount
  self.last_mouse_down_count = set_mouse_down_count.min(
    self.last_mouse_down_position_equal_count,
  )
}

///|
/// FFI gap-fill: whether a raw mouse event's target sits inside `container`
/// (`viewDomNode.contains(e.target)`, mouseHandler.ts:106).
extern "js" fn mouse_event_target_within(
  mouse : @rdom.MouseEvent,
  container : @rdom.Element,
) -> Bool =
  #| (m, container) => container.contains(m.target)

///|
pub extend NavigationCommandRevealType with Debug::{to_repr}

///|
pub extend NavigationCommandRevealType with Eq::{equal, not_equal}
