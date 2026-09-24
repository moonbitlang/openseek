///|
/// Keep the preferred width on the grid so the mobile stylesheet can override
/// the visible column without losing the desktop preference.
fn install_explorer_resize_handle() -> () -> Unit {
  let document : @js.Nullable[@rdom.Document] = @js.globalThis.get_with_string(
    "document",
  )
  guard document.to_option() is Some(document) else { return () => () }
  guard document.query_selector(".editor-main").to_option() is Some(main) else {
    return () => ()
  }
  guard document.query_selector("#workspace-explorer").to_option() is Some(_) else {
    return () => ()
  }
  guard document.query_selector("[data-action=\"resize-explorer\"]").to_option()
    is Some(handle) else {
    return () => ()
  }
  let owner_document : @rdom.Document = @js.Value::cast_from(handle).get_with_string(
    "ownerDocument",
  )
  let owner_window : @js.Nullable[@rdom.Window] = @js.Value::cast_from(
    owner_document,
  ).get_with_string("defaultView")
  let window = owner_window.to_option().unwrap_or(@rdom.window())
  guard owner_document.get_body() is Some(body) else { return () => () }
  let events = window.to_event_target()
  fn maximum_width() -> Int {
    let viewport = window.inner_width()
    let viewport = if viewport == 0.0 { 840.0 } else { viewport }
    let maximum = (viewport * 0.5).floor().to_int()
    if maximum < 200 {
      200
    } else if maximum > 420 {
      420
    } else {
      maximum
    }
  }
  fn is_mobile() -> Bool {
    window.match_media("(max-width: 680px)").get_matches()
  }
  let initial = window
    .get_computed_style(main)
    .get_property_value("--explorer-width")
  let parsed : Double = @js.globalThis.apply_with_string("parseFloat", [initial])
  let mut width = if parsed.is_nan() || parsed.round() == 0.0 {
    280
  } else {
    parsed.round().to_int()
  }
  // One optional drag owns both the pointer identity and the styles to restore.
  let mut drag : ExplorerDrag? = None
  fn write_width() -> Unit {
    @base_browser.set_style_property(main, "--explorer-width", "\{width}px")
    handle.set_attribute("aria-valuenow", width.to_string())
  }
  fn apply_width(next : Double) -> Unit {
    let maximum = maximum_width()
    width = if next < 200.0 {
      200
    } else if next > maximum.to_double() {
      maximum
    } else {
      next.round().to_int()
    }
    write_width()
    handle.set_attribute("aria-valuemax", maximum.to_string())
  }
  fn move_drag(event : @rdom.Event) -> Unit {
    guard drag is Some(active) else { return }
    guard event.to_pointer_event() is Some(pointer) else { return }
    if pointer.get_pointer_id() == active.pointer_id {
      apply_width(
        active.start_width.to_double() + pointer.get_client_x() - active.start_x,
      )
    }
  }
  fn finish_drag() -> Unit {
    guard drag is Some(active) else { return }
    try_pointer_capture(handle, active.pointer_id, false)
    drag = None
    events.remove_event_listener("pointermove", move_drag)
    body.get_style().set_property("cursor", active.cursor)
    body.get_style().set_property("user-select", active.user_select)
  }
  fn on_finish(event : @rdom.Event) -> Unit {
    guard event.to_pointer_event() is Some(pointer) else { return }
    if drag is Some(active) && pointer.get_pointer_id() == active.pointer_id {
      finish_drag()
      events.remove_event_listener("pointerup", on_finish)
      events.remove_event_listener("pointercancel", on_finish)
    }
  }
  fn start_drag(event : @rdom.Event) -> Unit {
    guard event.to_pointer_event() is Some(pointer) else { return }
    if pointer.get_button() != 0 || is_mobile() {
      return
    }
    event.prevent_default()
    drag = Some({
      pointer_id: pointer.get_pointer_id(),
      start_x: pointer.get_client_x(),
      start_width: width,
      cursor: body.get_style().get_property_value("cursor"),
      user_select: body.get_style().get_property_value("user-select"),
    })
    body.get_style().set_property("cursor", "ew-resize")
    body.get_style().set_property("user-select", "none")
    try_pointer_capture(handle, pointer.get_pointer_id(), true)
    events.add_event_listener("pointermove", move_drag)
    events.add_event_listener("pointerup", on_finish)
    events.add_event_listener("pointercancel", on_finish)
  }
  fn on_key_down(event : @rdom.Event) -> Unit {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    let next = match keyboard.key() {
      "ArrowLeft" => width - 10
      "ArrowRight" => width + 10
      "Home" => 200
      "End" => maximum_width()
      _ => return
    }
    event.prevent_default()
    apply_width(next.to_double())
  }
  fn on_window_resize(_event : @rdom.Event) -> Unit {
    if is_mobile() {
      let maximum = maximum_width()
      handle.set_attribute(
        "aria-valuemax",
        (if width > maximum { width } else { maximum }).to_string(),
      )
    } else {
      apply_width(width.to_double())
    }
  }
  if is_mobile() {
    write_width()
    let maximum = maximum_width()
    handle.set_attribute(
      "aria-valuemax",
      (if width > maximum { width } else { maximum }).to_string(),
    )
  } else {
    apply_width(width.to_double())
  }
  handle.add_event_listener("pointerdown", start_drag)
  handle.add_event_listener("keydown", on_key_down)
  events.add_event_listener("resize", on_window_resize)
  () => {
    finish_drag()
    events.remove_event_listener("pointerup", on_finish)
    events.remove_event_listener("pointercancel", on_finish)
    handle.remove_event_listener("pointerdown", start_drag)
    handle.remove_event_listener("keydown", on_key_down)
    events.remove_event_listener("resize", on_window_resize)
  }
}

///|
priv struct ExplorerDrag {
  pointer_id : Int
  start_x : Double
  start_width : Int
  cursor : String
  user_select : String
}

///|
fn try_pointer_capture(
  handle : @rdom.Element,
  id : Int,
  capture : Bool,
) -> Unit {
  @js.Error_::wrap(
    () => {
      if capture {
        handle.set_pointer_capture(id)
      } else {
        handle.release_pointer_capture(id)
      }
      @js.Value::cast_from(())
    },
    map_ok=_ => (),
  ) catch {
    _ => ()
  }
}
