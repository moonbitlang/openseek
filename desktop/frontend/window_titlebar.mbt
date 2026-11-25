// CSS supplies the desired header style. Proton owns the actual control
// geometry, which this window-local subscription mirrors back into CSS.

///|
const WindowTitlebarSelector = ".sidebar-header, .topbar, .editor-tabsbar"

///|
const WindowTitlebarExcludedSelector = "button, a, input, textarea, select, [role=button], [contenteditable=true], .editor-tab, .dock-menu"

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
fn publish_titlebar_area(area : TitlebarArea?, custom~ : Bool) -> Unit {
  guard @dom.document().get_document_element() is Some(root) &&
    root.to_html_element() is Some(html) else {
    return
  }
  titlebar_overlay_classes(root, area is Some(_), custom)
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
fn desired_titlebar_style(
  dark : Bool,
  dialog_depth : Int32,
) -> @protocol.AppTitlebarStylePayload? {
  guard @dom.document().get_document_element() is Some(root) else {
    return None
  }
  let css = @dom.window().get_computed_style(root)
  let height = css.get_property_value("--app-header-height").trim().to_owned()
  guard height.strip_suffix("px") is Some(pixels) else { return None }
  let height = @string.parse_double(pixels) catch { _ => return None }
  let palette = if dark { "dark" } else { "light" }
  let color = name => {
    let token = css.get_property_value("--\{palette}-\{name}").trim().to_owned()
    if dialog_depth == 0 {
      token
    } else {
      titlebar_dialog_color(token, dialog_depth)
    }
  }
  Some({
    dark,
    height,
    background_color: color("bg-canvas"),
    symbol_color: color("text-muted"),
  })
}

///|
priv struct TitlebarGeometry {
  bridge : @js.Value
  mut dark : Bool
  mut font_size : AppFontSize?
  mut applied_style : (@protocol.AppTitlebarStylePayload, Double)?
  mut custom_overlay : Bool
  mut dialog_depth : Int32
  mut immediate : Bool
  mut active : Bool
  mut revision : Int32
  mut in_flight : Bool
  mut frame : Double?
}

///|
fn TitlebarGeometry::refresh(self : TitlebarGeometry) -> Unit {
  self.revision += 1
  self.schedule()
}

///|
async fn TitlebarGeometry::apply_style(self : TitlebarGeometry) -> Unit {
  guard desired_titlebar_style(
      self.dark,
      if self.custom_overlay {
        self.dialog_depth
      } else {
        0
      },
    )
    is Some(style) else {
    return
  }
  // Page zoom can change the CSS-to-DIP conversion without a font setting
  // change. A changed CSS-to-device-pixel ratio also catches that case.
  let key = (style, @base_browser.device_pixel_ratio())
  guard self.applied_style != Some(key) else { return }
  let reply = @interop.bridge_request(
    @interop.ChannelId::Local,
    @commands.app_set_titlebar_style,
    style,
  )
  self.applied_style = Some(key)
  self.custom_overlay = reply.custom_overlay
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
  self.immediate = false
  self.in_flight = true
  let was_custom = self.custom_overlay
  // Wait for the host to apply height and colors before publishing geometry.
  // If styling fails, still read the system overlay so controls remain usable.
  self.apply_style() catch {
    error =>
      if self.active && requested == self.revision {
        titlebar_error("Titlebar styling failed: \{error}")
      }
  }
  try {
    let value = read_titlebar_area(self.bridge).wait()
    if self.active && requested == self.revision {
      publish_titlebar_area(
        decode_titlebar_area(value),
        custom=self.custom_overlay,
      )
    }
  } catch {
    error =>
      if self.active && requested == self.revision {
        titlebar_error("Titlebar geometry query failed: \{error}")
      }
  }
  self.in_flight = false
  if self.active &&
    (
      self.immediate ||
      (!was_custom && self.custom_overlay && self.dialog_depth > 0)
    ) {
    self.read()
  } else if requested != self.revision {
    self.schedule()
  }
}

///|
/// Only a successful, current reply can publish geometry; null means no overlay.
fn install_window_titlebar_geometry(
  dark : Bool,
  font_size : AppFontSize?,
) -> (() -> Unit, (Bool, AppFontSize?) -> Unit) {
  guard @interop.moonbit_bridge_root() is Some(bridge) &&
    @interop.js_prop(bridge, "getTitlebarArea") is Some(_) &&
    @interop.js_prop(bridge, "events") is Some(events) &&
    @interop.js_prop(events, "on") is Some(_) else {
    titlebar_error("Proton titlebar bridge unavailable")
    return (() => publish_titlebar_area(None, custom=false), (_, _) => ())
  }
  let state : TitlebarGeometry = {
    bridge,
    dark,
    font_size,
    applied_style: None,
    custom_overlay: false,
    dialog_depth: 0,
    immediate: false,
    active: true,
    revision: 0,
    in_flight: false,
    frame: None,
  }
  let unsubscribe_dialogs = subscribe_titlebar_dialogs(depth => {
    guard state.dialog_depth != depth else { return }
    state.dialog_depth = depth
    guard state.custom_overlay else { return }
    state.revision += 1
    state.immediate = true
    if !state.in_flight {
      if state.frame is Some(frame) {
        @dom.window().cancel_animation_frame(frame)
      }
      ignore(@js.Promise::from_async(() => state.read()))
    }
  })
  let listener : @dom.Listener = _ => state.refresh()
  let unsubscribe = subscribe_titlebar_changes(bridge, () => state.refresh())
  let window = @dom.window().to_event_target()
  let document = @dom.document().as_event_target()
  window.add_event_listener("resize", listener)
  window.add_event_listener("focus", listener)
  document.add_event_listener("visibilitychange", listener)
  state.refresh()
  (
    () => {
      state.active = false
      if state.frame is Some(frame) {
        @dom.window().cancel_animation_frame(frame)
      }
      unsubscribe_dialogs()
      unsubscribe()
      window.remove_event_listener("resize", listener)
      window.remove_event_listener("focus", listener)
      document.remove_event_listener("visibilitychange", listener)
      publish_titlebar_area(None, custom=false)
    },
    (dark, font_size) => {
      if dark != state.dark || font_size != state.font_size {
        state.dark = dark
        state.font_size = font_size
        state.refresh()
      }
    },
  )
}

///|
priv suberror WindowTitlebarSubscription {
  WindowTitlebarSubscription(Bool, AppFontSize?, @cmd.Emit[Unit])
}

///|
fn window_titlebar_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    WindowTitlebarSubscription(dark, font_size, emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let (uninstall_geometry, update_style) = install_window_titlebar_geometry(
        dark, font_size,
      )
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
          uninstall_geometry()
          target.remove_event_listener_with_options(
            "dblclick",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is WindowTitlebarSubscription(dark, font_size, next) else {
            return
          }
          emit = next
          update_style(dark, font_size)
        },
      })
    }
    _ => None
  }
}

///|
/// Install only in the native desktop page. Proton decides whether the current
/// window has an overlay; browser clients never query native window geometry.
fn window_titlebar_subscription(
  dark : Bool,
  font_size : AppFontSize?,
  emit : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(
    "window-titlebar",
    Global,
    WindowTitlebarSubscription(dark, font_size, emit),
    window_titlebar_sub_loader,
  )
}
