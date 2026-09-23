// Proton owns native control geometry; this window-local subscription mirrors
// its available titlebar area into CSS. CSS declares the page's drag regions.

///|
const WindowTitlebarSelector = ".sidebar-header, .topbar, .editor-tabsbar, .window-titlebar-drag-strip"

///|
const WindowTitlebarExcludedSelector = "button, a, input, textarea, select, [role=button], [contenteditable=true], .editor-tab, .dock-menu"

///|
fn window_titlebar_drag_strip_visible(
  page_without_topbar : Bool,
  is_desktop : Bool,
) -> Bool {
  page_without_topbar && is_desktop
}

///|
fn is_window_titlebar_double_click_target(element : @dom.Element) -> Bool {
  if element.closest(WindowTitlebarExcludedSelector) is Some(_) {
    return false
  }
  element.closest(WindowTitlebarSelector) is Some(_)
}

///|
priv struct TitlebarArea {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
priv suberror InvalidTitlebarArea {
  InvalidTitlebarArea
}

///|
impl Show for InvalidTitlebarArea with fn output(_, logger) {
  logger.write_string("Invalid Proton titlebar area")
}

///|
fn titlebar_number(
  value : @js.Value,
  name : String,
) -> Double raise InvalidTitlebarArea {
  let field : @js.Value = value.get_with_string(name)
  guard (@js.Cast::into(field) : Double?) is Some(number) &&
    !number.is_nan() &&
    !number.is_inf() else {
    raise InvalidTitlebarArea
  }
  number
}

///|
fn decode_titlebar_area(
  value : @js.Value,
) -> TitlebarArea? raise InvalidTitlebarArea {
  if value.is_null() {
    return None
  }
  if !value.is_object() {
    raise InvalidTitlebarArea
  }
  let area : TitlebarArea = {
    x: titlebar_number(value, "x"),
    y: titlebar_number(value, "y"),
    width: titlebar_number(value, "width"),
    height: titlebar_number(value, "height"),
  }
  if area.x < 0 || area.y < 0 || area.width <= 0 || area.height <= 0 {
    raise InvalidTitlebarArea
  }
  Some(area)
}

///|
fn publish_titlebar_area(area : TitlebarArea?) -> Unit {
  guard @dom.document().get_document_element() is Some(root) &&
    root.to_html_element() is Some(html) else {
    return
  }
  titlebar_overlay_class(root, area is Some(_))
  let style = html.get_style()
  match area {
    None =>
      for name in ["left", "right", "height"] {
        ignore(style.remove_property("--native-titlebar-\{name}"))
      }
    Some(area) => {
      style.set_property("--native-titlebar-left", "\{area.x}px")
      let right = @cmp.maximum(
        0.0,
        @dom.window().inner_width() - area.x - area.width,
      )
      style.set_property("--native-titlebar-right", "\{right}px")
      style.set_property(
        "--native-titlebar-height",
        "\{area.y + area.height}px",
      )
    }
  }
}

///|
priv struct TitlebarGeometry {
  bridge : @js.Value
  mut active : Bool
  mut revision : Int
  mut in_flight : Bool
  mut frame : Double?
}

///|
fn TitlebarGeometry::schedule(self : TitlebarGeometry) -> Unit {
  if self.active && !self.in_flight && self.frame is None {
    self.frame = Some(
      @dom.window().request_animation_frame(_ => {
        ignore(@js.Promise::from_async(() => self.read()))
      }),
    )
  }
}

///|
async fn TitlebarGeometry::read(self : TitlebarGeometry) -> Unit {
  self.frame = None
  let requested = self.revision
  self.in_flight = true
  try {
    let value = read_titlebar_area(self.bridge).wait()
    if self.active && requested == self.revision {
      publish_titlebar_area(decode_titlebar_area(value))
    }
  } catch {
    error =>
      if self.active && requested == self.revision {
        titlebar_error("Titlebar geometry query failed: \{error}")
      }
  }
  self.in_flight = false
  if requested != self.revision {
    self.schedule()
  }
}

///|
/// Own the query revision and subscription lifetime in MoonBit. Only a
/// successful, current reply can publish geometry; null means no overlay.
fn install_window_titlebar_geometry() -> () -> Unit {
  let bridge : @js.Value = @js.globalThis.get_with_string("__MoonBit__")
  guard !bridge.is_null() &&
    !bridge.is_undefined() &&
    @interop.js_prop(bridge, "getTitlebarArea") is Some(_) &&
    @interop.js_prop(bridge, "events") is Some(events) &&
    @interop.js_prop(events, "on") is Some(_) else {
    titlebar_error("Proton titlebar bridge unavailable")
    return () => publish_titlebar_area(None)
  }
  let state : TitlebarGeometry = {
    bridge,
    active: true,
    revision: 0,
    in_flight: false,
    frame: None,
  }
  let refresh = () => {
    state.revision += 1
    state.schedule()
  }
  let listener : @dom.Listener = _ => refresh()
  let unsubscribe = subscribe_titlebar_changes(bridge, refresh)
  let window = @dom.window().to_event_target()
  let document = @dom.document().as_event_target()
  window.add_event_listener("resize", listener)
  window.add_event_listener("focus", listener)
  document.add_event_listener("visibilitychange", listener)
  refresh()
  () => {
    state.active = false
    if state.frame is Some(frame) {
      @dom.window().cancel_animation_frame(frame)
    }
    unsubscribe()
    window.remove_event_listener("resize", listener)
    window.remove_event_listener("focus", listener)
    document.remove_event_listener("visibilitychange", listener)
    publish_titlebar_area(None)
  }
}

///|
priv suberror WindowTitlebarSubscription {
  WindowTitlebarSubscription(@cmd.Emit[Unit])
}

///|
fn window_titlebar_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    WindowTitlebarSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let geometry = install_window_titlebar_geometry()
      let listener : @dom.Listener = event => {
        guard window_titlebar_overlay_visible() &&
          event.to_mouse_event() is Some(mouse) &&
          mouse.get_button() == 0 &&
          event.target().to_element() is Some(element) &&
          is_window_titlebar_double_click_target(element) else {
          return
        }
        // A title or workspace label is text in the DOM, but within window
        // chrome it behaves as chrome rather than selectable document text.
        event.prevent_default()
        scheduler.add(emit(()))
      }
      target.add_event_listener_with_options("dblclick", listener, capture=true)
      Some({
        unload: _ => {
          geometry()
          target.remove_event_listener_with_options(
            "dblclick",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is WindowTitlebarSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// Install only in the native desktop page. Proton decides whether the current
/// window has an overlay; browser clients never query native window geometry.
fn window_titlebar_subscription(emit : @cmd.Emit[Unit]) -> @sub.Sub {
  @sub.custom_sub(
    "window-titlebar-double-click",
    Global,
    WindowTitlebarSubscription(emit),
    window_titlebar_sub_loader,
  )
}
