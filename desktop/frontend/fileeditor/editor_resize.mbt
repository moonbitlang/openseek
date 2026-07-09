// Drag-to-resize for the editor side-panel. The panel's width is a CSS custom
// property `--editor-width` on the document element, set imperatively as the
// user drags a handle on the panel's left edge — never through the model, so a
// drag never re-renders the (possibly large) transcript. The grid in
// `index.html` reads the property through a `clamp(...)`, so the bounds live in
// CSS and survive a window resize on their own.

///|
/// The id of the grab strip the view renders on the editor's left edge.
const ResizeHandleId = "editor-resize-handle"

///|
/// The class toggled on the document element for the duration of a drag, so CSS
/// can show the resize cursor and suppress text selection everywhere.
const ResizingClass = "is-resizing"

///|
/// The editor never shrinks below this. A hard floor only — collapse the tree
/// column to give a narrow editor more room for the viewer. Mirrors the CSS
/// `clamp` floor.
const MinEditorWidth = 360

///|
/// Width (px) always left to the conversation column, so a drag can never
/// swallow the chat entirely. Measured against the content area (sidebar
/// excluded), so it holds whether or not the sidebar is collapsed. Mirrors the
/// CSS `clamp` ceiling, `calc(100% - 240px)`.
const MinChatWidth = 240

///|
/// Whether the drag listeners have been installed yet (once, after first paint).
let resize_installed : Ref[Bool] = Ref(false)

///|
/// Whether a drag is in progress. The document-level move/up listeners are
/// permanent and simply gate on this, so there is nothing to add and remove per
/// drag.
let resizing : Ref[Bool] = Ref(false)

///|
/// Whether a viewer re-measure is already queued for the next frame, so a burst
/// of `mousemove`s re-measures at most once per frame.
let remeasure_pending : Ref[Bool] = Ref(false)

///|
/// Install the resize listeners once the handle is in the DOM: a `mousedown` on
/// the handle starts a drag, and document-level `mousemove` / `mouseup`
/// (capture, so they fire even while the cursor is over the viewer's own DOM)
/// carry and end it. Idempotent — a no-op once installed.
fn request_resize_handle_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => {
      if resize_installed.val {
        return
      }
      guard @dom.document().get_element_by_id(ResizeHandleId).to_option()
        is Some(handle) else {
        return
      }
      @interop.add_capture_listener(
        @js.Value::cast_from(handle),
        "mousedown",
        start_resize,
      )
      let document : @js.Value = @js.globalThis.get_with_string("document")
      @interop.add_capture_listener(document, "mousemove", on_resize_move)
      @interop.add_capture_listener(document, "mouseup", end_resize)
      resize_installed.val = true
    },
    kind=@cmd.after_render,
  )
}

///|
/// Begin a drag on a left-button press over the handle.
fn start_resize(event : @dom.Event) -> Unit {
  guard event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 else {
    return
  }
  // Stop the press from starting a text selection in the viewer underneath.
  event.prevent_default()
  resizing.val = true
  set_root_class(ResizingClass)
}

///|
/// Track the cursor. The editor is the rightmost column of `.content`, so its
/// right edge is the content's right edge and its width is the gap from the
/// cursor to that edge. Bounds are measured against the content area itself, so
/// the travel is as wide as the layout allows and is unaffected by the sidebar
/// being open or collapsed.
fn on_resize_move(event : @dom.Event) -> Unit {
  guard resizing.val &&
    event.to_mouse_event() is Some(mouse) &&
    @dom.document().query_selector(".content").to_option() is Some(content) else {
    return
  }
  let rect = content.get_bounding_client_rect()
  let floor = MinEditorWidth.to_double()
  let max = rect.get_width() - MinChatWidth.to_double()
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
  set_editor_width(width.to_int())
  schedule_remeasure()
}

///|
/// End the drag and give the viewer a final, exact re-measure.
fn end_resize(_event : @dom.Event) -> Unit {
  guard resizing.val else { return }
  resizing.val = false
  set_root_class("")
  if mounted_viewer() is Some(viewer) {
    viewer.layout()
  }
}

///|
/// The dragged sizes, kept so the resizers (editor width, tree height, tree
/// width) can rewrite the shared root `style` attribute without erasing each
/// other's property.
let editor_width : Ref[Int?] = Ref(None)

///|
let tree_height : Ref[Int?] = Ref(None)

///|
let tree_width : Ref[Int?] = Ref(None)

///|
/// Write the dragged sizes as custom properties on the document element,
/// where the CSS `clamp(...)`s read them. Set on the root, not on the panes
/// themselves, so a rabbita re-render never clears them.
fn sync_root_style() -> Unit {
  guard document_element() is Some(root) else { return }
  let style = StringBuilder::new()
  if editor_width.val is Some(width) {
    style.write_string("--editor-width: \{width}px;")
  }
  if tree_height.val is Some(height) {
    style.write_string("--tree-height: \{height}px;")
  }
  if tree_width.val is Some(width) {
    style.write_string("--tree-width: \{width}px;")
  }
  root.set_attribute("style", style.to_string())
}

///|
fn set_editor_width(width : Int) -> Unit {
  editor_width.val = Some(width)
  sync_root_style()
}

///|
fn set_tree_height(height : Int) -> Unit {
  tree_height.val = Some(height)
  sync_root_style()
}

///|
fn set_tree_width(width : Int) -> Unit {
  tree_width.val = Some(width)
  sync_root_style()
}

///|
/// Toggle a class on the document element (empty string clears it).
fn set_root_class(class_name : String) -> Unit {
  if document_element() is Some(root) {
    root.set_attribute("class", class_name)
  }
}

///|
fn document_element() -> @dom.Element? {
  @dom.document().query_selector("html").to_option()
}

///|
/// Re-measure the viewer at most once per animation frame while dragging, so a
/// flood of `mousemove`s does not thrash its layout (the viewer fills its host
/// with absolutely-positioned layers and cannot see a CSS width change itself).
fn schedule_remeasure() -> Unit {
  if remeasure_pending.val || mounted_viewer() is None {
    return
  }
  remeasure_pending.val = true
  @dom.window().request_animation_frame(_ => {
    remeasure_pending.val = false
    if mounted_viewer() is Some(viewer) {
      viewer.layout()
    }
  })
  |> ignore
}
