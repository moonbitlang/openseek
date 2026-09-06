// Drag-to-resize for the sidebar (the projects panel). The panel's width is a
// CSS custom property `--sidebar-width` on the document element, set
// imperatively as the user drags a handle on the aside's right edge — never
// through the model, so a drag never re-renders the app. The `.app` grid in
// `base.css` reads the property through a `clamp(...)`, so the bounds live in
// CSS and survive a window resize on their own. Mirrors the editor panel's
// resize (fileeditor/editor_resize.mbt).

///|
/// The class toggled on the document element for the duration of a drag —
/// the same one the fileeditor resizers use, so the shared CSS shows the
/// resize cursor and suppresses text selection everywhere for both drags.
const ResizingClass = "is-resizing"

///|
/// The sidebar never shrinks below this. Mirrors the CSS `clamp` floor.
const MinSidebarWidth = 220

///|
/// The sidebar never grows past this. Mirrors the CSS `clamp` ceiling.
const MaxSidebarWidth = 480

///|
/// Width (px) always left to the content column, so a drag can never squeeze
/// the conversation out of existence. Plays the role the editor drag's
/// `MinChatWidth` plays there.
const MinContentWidth = 360

///|
/// Whether the drag listeners have been installed yet (once, after first
/// paint).
let sidebar_resize_installed : Ref[Bool] = Ref(false)

///|
/// Whether a sidebar drag is in progress. The document-level move/up
/// listeners are permanent and simply gate on this, so there is nothing to
/// add and remove per drag.
let sidebar_resizing : Ref[Bool] = Ref(false)

///|
/// Install the resize listeners once the handle is in the DOM: a `mousedown`
/// on the handle starts a drag, and document-level `mousemove` / `mouseup`
/// (capture, so they fire even while the cursor is over the conversation's
/// own DOM) carry and end it. Idempotent — a no-op once installed.
pub fn request_sidebar_resize_mount() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _after => {
      if sidebar_resize_installed.val {
        return
      }
      guard @dom.document()
        .get_element_by_id(@sidebar.ResizeHandleId)
        .to_option()
        is Some(handle) else {
        return
      }
      @interop.add_capture_listener(
        @js.Value::cast_from(handle),
        "mousedown",
        start_sidebar_resize,
      )
      let document : @js.Value = @js.globalThis.get_with_string("document")
      @interop.add_capture_listener(
        document, "mousemove", on_sidebar_resize_move,
      )
      @interop.add_capture_listener(document, "mouseup", _ => {
        end_sidebar_resize()
      })
      sidebar_resize_installed.val = true
    },
    kind=@cmd.after_render,
  )
}

///|
/// Begin a drag on a left-button press over the handle.
fn start_sidebar_resize(event : @dom.Event) -> Unit {
  guard event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 else {
    return
  }
  // Stop the press from starting a text selection in the sidebar underneath.
  event.prevent_default()
  sidebar_resizing.val = true
  set_root_class(ResizingClass)
}

///|
/// Track the cursor. The sidebar is the leftmost column of `.app`, so its
/// width is the gap from the app's left edge to the cursor. The ceiling
/// keeps at least `MinContentWidth` for the content column; on a very
/// narrow window the floor wins, even past the ceiling.
fn on_sidebar_resize_move(event : @dom.Event) -> Unit {
  guard sidebar_resizing.val &&
    event.to_mouse_event() is Some(mouse) &&
    @dom.document().query_selector(".app").to_option() is Some(app) else {
    return
  }
  let rect = app.get_bounding_client_rect()
  set_sidebar_width(
    drag_width(
      mouse.get_client_x() - rect.get_left(),
      ceiling=rect.get_width() - MinContentWidth.to_double(),
    ),
  )
}

///|
/// Clamp the dragged width into the sidebar's allowed range.
fn drag_width(raw : Double, ceiling~ : Double) -> Int {
  let ceiling = ceiling.clamp(
    min=MinSidebarWidth.to_double(),
    max=MaxSidebarWidth.to_double(),
  )
  raw.clamp(min=MinSidebarWidth.to_double(), max=ceiling).to_int()
}

///|
/// End a drag.
fn end_sidebar_resize() -> Unit {
  guard sidebar_resizing.val else { return }
  sidebar_resizing.val = false
  set_root_class("")
}

///|
/// Write the dragged width as a custom property on the document element,
/// where the CSS `clamp(...)` reads it.
fn set_sidebar_width(width : Int) -> Unit {
  set_root_custom_property("--sidebar-width", "\{width}px")
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
