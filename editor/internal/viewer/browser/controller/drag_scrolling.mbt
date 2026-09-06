// Ported from `vscode/src/vs/editor/browser/controller/dragScrolling.ts`
// (checked-in vscode submodule): the
// edge auto-scroll that keeps a selection drag going while the pointer sits
// outside the editor.
//
// Shape notes:
//   * The source's four classes (`TopBottomDragScrolling`/
//     `LeftRightDragScrolling` and their operations, each a thin subclass of
//     an abstract base) collapse into one struct pair discriminated by
//     `DragScrollingDirection` — MoonBit has no inheritance, and the only
//     variance is `_getScrollSpeed`/`_execute`.
//   * `_context.configuration.options` reads ride on the helper
//     (`get_font_info`/`get_layout_info`); `deltaScrollNow` is
//     `ViewLayout::scroll_by` + the helper's `apply_scroll`.
//   * `viewportData.startLineNumber/endLineNumber`
//     (`getLinesViewportData`) map to the layout's `visible_window()`
//     (1-based half-open, so `end - 1` is the inclusive edge line).
//
// Omissions:
//   * The `LeftRight` operation's `!this._position.position` null-check —
//     this port's `MouseTargetOutsideEditor` always carries a position.

///|
priv enum DragScrollingDirection {
  TopBottom
  LeftRight
}

///|
/// `DragScrolling` (dragScrolling.ts:17-52).
priv struct DragScrolling {
  direction : DragScrollingDirection
  view_helper : PointerHandlerHelper
  mouse_target_factory : MouseTargetFactory
  mut dispatch_mouse : (
    @editor_browser.MouseTarget,
    Bool,
    NavigationCommandRevealType,
  ) -> Unit
  mut operation : DragScrollingOperation?
}

///|
/// Rebinds the dispatch seam. Monaco passes
/// `(position, inSelectionMode, revealType) => this._dispatchMouse(...)`
/// straight into the constructor; the `MouseDownOperation` here can only
/// close over itself after construction, so the closure is installed
/// immediately afterwards (mouse_handler.mbt).
fn DragScrolling::set_dispatch(
  self : DragScrolling,
  dispatch_mouse : (
    @editor_browser.MouseTarget,
    Bool,
    NavigationCommandRevealType,
  ) -> Unit,
) -> Unit {
  self.dispatch_mouse = dispatch_mouse
}

///|
fn DragScrolling::DragScrolling(
  direction : DragScrollingDirection,
  view_helper : PointerHandlerHelper,
  mouse_target_factory : MouseTargetFactory,
  dispatch_mouse : (
    @editor_browser.MouseTarget,
    Bool,
    NavigationCommandRevealType,
  ) -> Unit,
) -> DragScrolling {
  {
    direction,
    view_helper,
    mouse_target_factory,
    dispatch_mouse,
    operation: None,
  }
}

///|
fn DragScrolling::dispose(self : DragScrolling) -> Unit {
  self.stop()
}

///|
/// `start` (dragScrolling.ts:36-42). `position` must be a
/// `MouseTargetOutsideEditor`.
fn DragScrolling::start(
  self : DragScrolling,
  position : @editor_browser.MouseTarget,
  mouse_event : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  match self.operation {
    Some(operation) => operation.set_position(position, mouse_event)
    None =>
      self.operation = Some(
        DragScrollingOperation(
          self.direction,
          self.view_helper,
          self.mouse_target_factory,
          self.dispatch_mouse,
          position,
          mouse_event,
        ),
      )
  }
}

///|
fn DragScrolling::stop(self : DragScrolling) -> Unit {
  if self.operation is Some(operation) {
    operation.dispose()
    self.operation = None
  }
}

///|
/// `DragScrollingOperation` (dragScrolling.ts:54-98) plus the per-direction
/// `_getScrollSpeed`/`_execute` bodies (dragScrolling.ts:106-158, 167-218).
priv struct DragScrollingOperation {
  direction : DragScrollingDirection
  view_helper : PointerHandlerHelper
  mouse_target_factory : MouseTargetFactory
  dispatch_mouse : (
    @editor_browser.MouseTarget,
    Bool,
    NavigationCommandRevealType,
  ) -> Unit
  mut position : @editor_browser.MouseTarget
  mut mouse_event : @editor_browser.EditorDomMouseEvent
  mut last_time : Double
  mut animation_frame_id : Double?
  mut disposed : Bool
}

///|
fn DragScrollingOperation::DragScrollingOperation(
  direction : DragScrollingDirection,
  view_helper : PointerHandlerHelper,
  mouse_target_factory : MouseTargetFactory,
  dispatch_mouse : (
    @editor_browser.MouseTarget,
    Bool,
    NavigationCommandRevealType,
  ) -> Unit,
  position : @editor_browser.MouseTarget,
  mouse_event : @editor_browser.EditorDomMouseEvent,
) -> DragScrollingOperation {
  let operation : DragScrollingOperation = {
    direction,
    view_helper,
    mouse_target_factory,
    dispatch_mouse,
    position,
    mouse_event,
    last_time: @base_browser.wall_clock_now_ms(),
    animation_frame_id: None,
    disposed: false,
  }
  operation.schedule()
  operation
}

///|
fn DragScrollingOperation::schedule(self : DragScrollingOperation) -> Unit {
  self.animation_frame_id = Some(
    @rdom.window().request_animation_frame(_ => {
      if !self.disposed {
        self.execute()
      }
    }),
  )
}

///|
fn DragScrollingOperation::dispose(self : DragScrollingOperation) -> Unit {
  self.disposed = true
  if self.animation_frame_id is Some(id) {
    @rdom.window().cancel_animation_frame(id)
  }
  self.animation_frame_id = None
}

///|
fn DragScrollingOperation::set_position(
  self : DragScrollingOperation,
  position : @editor_browser.MouseTarget,
  mouse_event : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  self.position = position
  self.mouse_event = mouse_event
}

///|
/// `_tick` (dragScrolling.ts:89-94): elapsed ms since the last frame.
fn DragScrollingOperation::tick(self : DragScrollingOperation) -> Double {
  let now = @base_browser.wall_clock_now_ms()
  let elapsed = now - self.last_time
  self.last_time = now
  elapsed
}

///|
/// The `(outside_position, outside_distance)` payload of the tracked
/// `MouseTargetOutsideEditor`.
fn DragScrollingOperation::outside_facts(
  self : DragScrollingOperation,
) -> (@editor_browser.OutsidePosition, Double) {
  match self.position {
    MouseTargetOutsideEditor(outside_position~, outside_distance~, ..) =>
      (outside_position, outside_distance)
    _ => (Above, 0.0)
  }
}

///|
/// `TopBottomDragScrollingOperation._getScrollSpeed` (dragScrolling.ts:111-123)
/// / `LeftRightDragScrollingOperation._getScrollSpeed` (dragScrolling.ts:172-183).
fn DragScrollingOperation::get_scroll_speed(
  self : DragScrollingOperation,
) -> Double {
  let font_info = (self.view_helper.get_font_info)()
  let layout_info = (self.view_helper.get_layout_info)()
  let (_, outside_distance) = self.outside_facts()
  let (viewport_in_units, outside_distance_in_units) = match self.direction {
    TopBottom => {
      let line_height = font_info.line_height.to_double()
      (layout_info.height / line_height, outside_distance / line_height)
    }
    LeftRight => {
      let char_width = font_info.typical_fullwidth_character_width
      (layout_info.content_width / char_width, outside_distance / char_width)
    }
  }
  if outside_distance_in_units <= 1.5 {
    30.0.max(viewport_in_units * (1.0 + outside_distance_in_units))
  } else if outside_distance_in_units <= 3.0 {
    60.0.max(viewport_in_units * (2.0 + outside_distance_in_units))
  } else {
    200.0.max(viewport_in_units * (7.0 + outside_distance_in_units))
  }
}

///|
/// `TopBottomDragScrollingOperation._execute` (dragScrolling.ts:125-158) /
/// `LeftRightDragScrollingOperation._execute` (dragScrolling.ts:185-218).
fn DragScrollingOperation::execute(self : DragScrollingOperation) -> Unit {
  guard (self.view_helper.view_model)() is Some(view_model) else { return }
  let font_info = (self.view_helper.get_font_info)()
  let layout_info = (self.view_helper.get_layout_info)()
  let (outside_position, outside_distance) = self.outside_facts()
  let scroll_speed = self.get_scroll_speed()
  let elapsed = self.tick()
  match self.direction {
    TopBottom => {
      let line_height = font_info.line_height.to_double()
      let scroll_in_pixels = scroll_speed * (elapsed / 1000.0) * line_height
      let scroll_value = if outside_position is Above {
        -scroll_in_pixels
      } else {
        scroll_in_pixels
      }
      view_model.view_layout.scroll_by(delta_top=scroll_value) |> ignore
      (self.view_helper.render_now)()
      let window = view_model.view_layout.visible_window()
      let edge_line_number = if outside_position is Above {
        window.start
      } else {
        window.end - 1
      }
      let cannot_scroll_anymore = if outside_position is Above {
        window.start == 1
      } else {
        window.end - 1 == view_model.line_count()
      }
      // First, try to find a position that matches the horizontal position
      // of the mouse
      let mut mouse_target = self.probe_mouse_target(layout_info)
      let position_matches_edge = match mouse_target.position() {
        Some(position) => position.line_number == edge_line_number
        None => false
      }
      if !position_matches_edge || cannot_scroll_anymore {
        mouse_target = if outside_position is Above {
          @editor_browser.MouseTarget::create_outside_editor(
            self.position.mouse_column(),
            Position(edge_line_number, 1),
            Above,
            outside_distance,
          )
        } else {
          @editor_browser.MouseTarget::create_outside_editor(
            self.position.mouse_column(),
            Position(
              edge_line_number,
              view_model.get_line_max_column(edge_line_number),
            ),
            Below,
            outside_distance,
          )
        }
      }
      (self.dispatch_mouse)(mouse_target, true, None)
      self.schedule()
    }
    LeftRight => {
      let char_width = font_info.typical_fullwidth_character_width
      let scroll_in_pixels = scroll_speed *
        (elapsed / 1000.0) *
        char_width *
        0.5
      let scroll_value = if outside_position is Left {
        -scroll_in_pixels
      } else {
        scroll_in_pixels
      }
      view_model.view_layout.scroll_by(delta_left=scroll_value) |> ignore
      (self.view_helper.render_now)()
      guard self.position.position() is Some(edge_position) else { return }
      let edge_line_number = edge_position.line_number
      // First, try to find a position that matches the horizontal position
      // of the mouse
      let probed = self.probe_mouse_target(layout_info)
      let mouse_target = @editor_browser.MouseTarget::create_outside_editor(
        probed.mouse_column(),
        Position(edge_line_number, probed.mouse_column()),
        if outside_position is Left {
          Left
        } else {
          Right
        },
        outside_distance,
      )
      (self.dispatch_mouse)(mouse_target, true, None)
      self.schedule()
    }
  }
}

///|
/// The shared probe both `_execute` bodies run (dragScrolling.ts:141-147,
/// 202-208): hit-test the mouse x at the last content row above the
/// horizontal scrollbar.
fn DragScrollingOperation::probe_mouse_target(
  self : DragScrollingOperation,
  layout_info : @config.EditorLayoutInfo,
) -> @editor_browser.MouseTarget {
  let editor_pos = @editor_browser.create_editor_page_position(
    self.view_helper.view_dom_node,
  )
  let pos : @editor_browser.PageCoordinates = {
    x: self.mouse_event.pos.x,
    y: editor_pos.y +
    editor_pos.height -
    layout_info.horizontal_scrollbar_height -
    0.1,
  }
  let relative_pos = @editor_browser.create_coordinates_relative_to_editor(
    self.view_helper.view_dom_node,
    editor_pos,
    pos,
  )
  self.mouse_target_factory.create_mouse_target(
    (self.view_helper.get_last_render_data)(),
    editor_pos,
    pos,
    relative_pos,
    None,
  )
}
