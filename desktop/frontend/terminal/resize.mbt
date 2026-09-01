// Drag-to-resize for the terminal's top seam. Like the editor resizers, the
// drag writes a CSS custom property directly instead of sending mousemove
// messages through the Rabbita model. The terminal host's ResizeObserver in
// host.mbt notices each size change and re-fits the visible xterm instance.

///|
/// The stable id of the grab strip rendered by `panel_view`.
const TerminalResizeHandleId = "terminal-resize-handle"

///|
/// The document class used while dragging to keep the row-resize cursor and
/// suppress text selection outside the narrow grab strip.
const TerminalResizingClass = "is-resizing-terminal"

///|
/// The terminal and conversation each keep at least this many pixels. These
/// values mirror the two bounds in `.content.terminal-open`'s CSS clamp.
const MinTerminalHeight = 180

///|
const MinConversationHeight = 180

///|
/// One process-wide listener set and its current drag state. The panel has one
/// stable handle for the application lifetime, so listeners install once and
/// remain gated by `active` between drags.
priv struct TerminalResizer {
  installed : Ref[Bool]
  active : Ref[Bool]
}

///|
let terminal_resizer : TerminalResizer = {
  installed: Ref(false),
  active: Ref(false),
}

///|
/// Install the handle and document listeners after the panel has rendered.
/// Idempotent: every first-tab mount may request it, but only the first call
/// that finds the stable handle performs the installation.
fn TerminalResizer::mount(self : TerminalResizer) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if self.installed.val {
        return
      }
      guard @dom.document()
        .get_element_by_id(TerminalResizeHandleId)
        .to_option()
        is Some(handle) else {
        return
      }
      @interop.add_capture_listener(@js.Value::cast_from(handle), "mousedown", event => {
        self.start(event)
      })
      let document : @js.Value = @js.globalThis.get_with_string("document")
      @interop.add_capture_listener(document, "mousemove", event => {
        self.track(event)
      })
      @interop.add_capture_listener(document, "mouseup", _ => self.finish())
      self.installed.val = true
    },
    kind=@cmd.after_render,
  )
}

///|
/// Begin a drag only for the primary mouse button.
fn TerminalResizer::start(self : TerminalResizer, event : @dom.Event) -> Unit {
  guard event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 else {
    return
  }
  event.prevent_default()
  self.active.val = true
  guard @dom.document().query_selector("html").to_option() is Some(root) else {
    return
  }
  let classes : @js.Value = @js.Value::cast_from(root).get_with_string(
    "classList",
  )
  let _ : @js.Value = classes.apply_with_string("add", [
    @js.Value::cast_from(TerminalResizingClass),
  ])
}

///|
/// Resize the second content-grid row from the pointer to the content area's
/// bottom edge. The floor wins if a short window cannot satisfy both bounds,
/// matching the CSS `clamp`.
fn TerminalResizer::track(self : TerminalResizer, event : @dom.Event) -> Unit {
  guard self.active.val &&
    event.to_mouse_event() is Some(mouse) &&
    @dom.document().query_selector(".content").to_option() is Some(content) else {
    return
  }
  let rect = content.get_bounding_client_rect()
  let floor = MinTerminalHeight.to_double()
  let max = rect.get_height() - MinConversationHeight.to_double()
  let ceiling = if max > floor { max } else { floor }
  let raw = rect.get_bottom() - mouse.get_client_y().to_double()
  let height = if raw < floor {
    floor
  } else if raw > ceiling {
    ceiling
  } else {
    raw
  }
  guard @dom.document().query_selector("html").to_option() is Some(root) else {
    return
  }
  let style : @js.Value = @js.Value::cast_from(root).get_with_string("style")
  let _ : @js.Value = style.apply_with_string("setProperty", [
    @js.Value::cast_from("--terminal-height"),
    @js.Value::cast_from("\{height.to_int()}px"),
  ])
}

///|
/// End the active drag and restore the document's normal cursor and selection.
fn TerminalResizer::finish(self : TerminalResizer) -> Unit {
  guard self.active.val else { return }
  self.active.val = false
  guard @dom.document().query_selector("html").to_option() is Some(root) else {
    return
  }
  let classes : @js.Value = @js.Value::cast_from(root).get_with_string(
    "classList",
  )
  let _ : @js.Value = classes.apply_with_string("remove", [
    @js.Value::cast_from(TerminalResizingClass),
  ])
}
