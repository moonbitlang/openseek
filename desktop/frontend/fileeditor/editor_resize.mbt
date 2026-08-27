// Drag-to-resize for the editor side-panel. The panel's width is a CSS custom
// property `--editor-width` on the document element, committed when a drag
// ends — never through the model, so a drag never re-renders the (possibly
// large) transcript. During the drag, the `.content` grid is written directly:
// changing an inherited root custom property on every move would invalidate
// styles across the whole transcript. The CSS `clamp(...)` remains the durable
// layout and survives a later window resize on its own.

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
/// A completed editor width owns both CSS spellings used by the drag. Keeping
/// the concrete track here makes the live value testable: malformed CSS is
/// otherwise silently ignored and the pane appears frozen until mouseup.
priv struct EditorWidth {
  pixels : Int
}

///|
fn EditorWidth::grid_template(self : EditorWidth) -> String {
  "minmax(0, 1fr) \{self.pixels}px"
}

///|
fn EditorWidth::custom_property(self : EditorWidth) -> String {
  "\{self.pixels}px"
}

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
      @interop.add_capture_listener(document, "mouseup", _ => end_drag(resizing))
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
  viewer_state.set_continuous_width_resize(true)
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
  set_editor_width(
    drag_size(
      rect.get_right() - mouse.get_client_x().to_double(),
      floor=MinEditorWidth.to_double(),
      max=rect.get_width() - MinChatWidth.to_double(),
    ),
  )
  schedule_remeasure()
}

///|
/// Clamp a dragged edge-to-cursor distance into the pane's allowed range.
/// Shared by the editor's width drag and both of the tree panel's axes.
/// On a very narrow window the floor wins, even past the ceiling.
fn drag_size(raw : Double, floor~ : Double, max~ : Double) -> Int {
  let ceiling = if max > floor { max } else { floor }
  let size = if raw < floor {
    floor
  } else if raw > ceiling {
    ceiling
  } else {
    raw
  }
  size.to_int()
}

///|
/// End a drag and give the viewer a final, exact re-measure. `active` is the
/// drag flag of whichever resizer is ending — see `resizing` / `tree_resizing`.
fn end_drag(active : Ref[Bool]) -> Unit {
  guard active.val else { return }
  let editor_drag_ended = resizing.val
  active.val = false
  set_root_class("")
  if editor_drag_ended {
    // Commit the final width once, then return ownership of the grid template
    // to CSS. This one root-style invalidation happens after pointer tracking,
    // not once per live frame.
    sync_root_style()
    if @dom.document().query_selector(".content").to_option() is Some(content) {
      let style : @js.Value = @js.Value::cast_from(content).get_with_string(
        "style",
      )
      let _ : @js.Value = style.apply_with_string("removeProperty", [
        @js.Value::cast_from("grid-template-columns"),
      ])
    }
  }
  viewer_state.set_continuous_width_resize(false)
  layout_active_editor_surface()
}

///|
/// The dragged sizes, kept so the resizers (editor width, tree height, tree
/// width) can rewrite the shared root `style` attribute without erasing each
/// other's property.
let editor_width : Ref[EditorWidth?] = Ref(None)

///|
let tree_height : Ref[Int?] = Ref(None)

///|
let tree_width : Ref[Int?] = Ref(None)

///|
/// Write the dragged sizes as individual custom properties on the document
/// element, where the CSS `clamp(...)`s read them. Updating properties through
/// CSSOM preserves sizes owned by other panels, including the terminal height;
/// setting one shared `style` attribute here would erase those values.
fn sync_root_style() -> Unit {
  guard document_element() is Some(root) else { return }
  let style : @js.Value = @js.Value::cast_from(root).get_with_string("style")
  if editor_width.val is Some(width) {
    let _ : @js.Value = style.apply_with_string("setProperty", [
      @js.Value::cast_from("--editor-width"),
      @js.Value::cast_from(width.custom_property()),
    ])
  }
  if tree_height.val is Some(height) {
    let _ : @js.Value = style.apply_with_string("setProperty", [
      @js.Value::cast_from("--tree-height"),
      @js.Value::cast_from("\{height}px"),
    ])
  }
  if tree_width.val is Some(width) {
    let _ : @js.Value = style.apply_with_string("setProperty", [
      @js.Value::cast_from("--tree-width"),
      @js.Value::cast_from("\{width}px"),
    ])
  }
}

///|
fn set_editor_width(width : Int) -> Unit {
  let value : EditorWidth = { pixels: width }
  editor_width.val = Some(value)
  if resizing.val &&
    @dom.document().query_selector(".content").to_option() is Some(content) {
    // The value has already been clamped against the live content box. Write
    // the concrete grid track instead of an inherited variable so the browser
    // only invalidates the layout that actually changed.
    let style : @js.Value = @js.Value::cast_from(content).get_with_string(
      "style",
    )
    let _ : @js.Value = style.apply_with_string("setProperty", [
      @js.Value::cast_from("grid-template-columns"),
      @js.Value::cast_from(value.grid_template()),
    ])
  } else {
    sync_root_style()
  }
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
/// Re-measure an active code or Markdown viewer at most once per animation
/// frame while dragging. DiffEditor owns a ResizeObserver on the same host, so
/// calling its layout here as well would render both panes twice for one width.
fn schedule_remeasure() -> Unit {
  if remeasure_pending.val ||
    (
      mounted_viewer() is None &&
      mounted_markdown_viewer() is None &&
      mounted_diff_editor() is None
    ) {
    return
  }
  remeasure_pending.val = true
  @dom.window().request_animation_frame(_ => {
    remeasure_pending.val = false
    layout_active_editor_surface(layout_observed_diff=false)
  })
  |> ignore
}
