// Drag-to-resize for the docked file-tree panel: a grab strip on the panel's
// viewer-facing seam sets the `--tree-height` (bottom layout) or
// `--tree-width` (right-sidebar layout) custom property imperatively as the
// user drags, mirroring the editor's left-edge resizer (editor_resize.mbt) —
// never through the model, so a drag never re-renders anything. The
// flex-basis `clamp(...)`s in index.html read the properties, so the bounds
// live in CSS and survive a window resize on their own. Which axis a drag
// works is read off the DOM (`.editor.tree-right`) at drag time, so the
// permanent listeners need no view of the Settings choice.

///|
/// The id of the grab strip the view renders on the tree panel's seam.
const TreeResizeHandleId = "tree-resize-handle"

///|
/// The classes toggled on the document element for the duration of a drag —
/// the tree-panel twins of `ResizingClass`, one per dock axis.
const RowResizingClass = "is-resizing-row"

///|
const ColResizingClass = "is-resizing-col"

///|
/// The bottom-docked tree never shrinks below this. Mirrors the CSS `clamp`
/// floor.
const MinTreeHeight = 96

///|
/// Height (px) always left to the viewer above, so a drag can never swallow
/// it entirely. Mirrors the CSS `clamp` ceiling, `calc(100% - 120px)`.
const MinViewerHeight = 120

///|
/// The sidebar-docked tree never shrinks below this. Mirrors the CSS `clamp`
/// floor.
const MinTreeWidth = 180

///|
/// Width (px) always left to the viewer beside it. Mirrors the CSS `clamp`
/// ceiling, `calc(100% - 240px)`.
const MinViewerWidth = 240

///|
/// Whether the panel is currently docked as the right sidebar — read off the
/// rendered layout class so the drag listeners follow the Settings choice
/// without holding state.
fn tree_docked_right() -> Bool {
  @dom.document().query_selector(".editor.tree-right").to_option() is Some(_)
}

///|
let tree_resize_installed : Ref[Bool] = Ref(false)

///|
let tree_resizing : Ref[Bool] = Ref(false)

///|
/// Install the drag listeners once the handle is in the DOM; same shape as
/// `request_resize_handle_mount`. Idempotent — a no-op once installed.
fn request_tree_resize_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      if tree_resize_installed.val {
        return
      }
      guard @dom.document().get_element_by_id(TreeResizeHandleId).to_option()
        is Some(handle) else {
        return
      }
      @interop.add_capture_listener(
        @js.Value::cast_from(handle),
        "mousedown",
        start_tree_resize,
      )
      let document : @js.Value = @js.globalThis.get_with_string("document")
      @interop.add_capture_listener(document, "mousemove", on_tree_resize_move)
      @interop.add_capture_listener(document, "mouseup", end_tree_resize)
      tree_resize_installed.val = true
    },
    kind=@cmd.after_render,
  )
}

///|
fn start_tree_resize(event : @dom.Event) -> Unit {
  guard event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 else {
    return
  }
  event.prevent_default()
  tree_resizing.val = true
  set_root_class(
    if tree_docked_right() {
      ColResizingClass
    } else {
      RowResizingClass
    },
  )
}

///|
/// Track the cursor. The panel is docked to the editor body's bottom or
/// right edge, so its size is the gap from the cursor to that edge.
fn on_tree_resize_move(event : @dom.Event) -> Unit {
  guard tree_resizing.val &&
    event.to_mouse_event() is Some(mouse) &&
    @dom.document().query_selector(".editor-body").to_option() is Some(body) else {
    return
  }
  let rect = body.get_bounding_client_rect()
  if tree_docked_right() {
    let floor = MinTreeWidth.to_double()
    let max = rect.get_width() - MinViewerWidth.to_double()
    // On a very narrow window the floor wins, even past the ceiling.
    let ceiling = if max > floor { max } else { floor }
    let raw = rect.get_right() - mouse.get_client_x().to_double()
    let width = if raw < floor {
      floor
    } else if raw > ceiling {
      ceiling
    } else {
      raw
    }
    set_tree_width(width.to_int())
  } else {
    let floor = MinTreeHeight.to_double()
    let max = rect.get_height() - MinViewerHeight.to_double()
    // On a very short window the floor wins, even past the ceiling.
    let ceiling = if max > floor { max } else { floor }
    let raw = rect.get_bottom() - mouse.get_client_y().to_double()
    let height = if raw < floor {
      floor
    } else if raw > ceiling {
      ceiling
    } else {
      raw
    }
    set_tree_height(height.to_int())
  }
  schedule_remeasure()
}

///|
/// End the drag and give the viewer a final, exact re-measure.
fn end_tree_resize(_event : @dom.Event) -> Unit {
  guard tree_resizing.val else { return }
  tree_resizing.val = false
  set_root_class("")
  if mounted_viewer() is Some(viewer) {
    viewer.layout()
  }
}
