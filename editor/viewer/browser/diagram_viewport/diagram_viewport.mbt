///|
let diagram_viewport_class = "moonbit-viewer-markdown-diagram-viewport"

///|
let diagram_content_class = "moonbit-viewer-markdown-diagram-content"

///|
let diagram_controls_class = "moonbit-viewer-markdown-diagram-controls"

///|
let diagram_resize_handle_class = "moonbit-viewer-markdown-diagram-resize-handle"

///|
let diagram_min_scale = 0.5

///|
let diagram_max_scale = 10.0

///|
let diagram_zoom_factor = 0.002

///|
let diagram_fit_padding = 16.0

///|
let diagram_maximum_initial_height = 480.0

///|
let diagram_initial_window_height_ratio = 0.5

///|
let diagram_minimum_height = 100.0

///|
let diagram_drag_threshold = 3.0

///|
priv struct SavedAttribute {
  present : Bool
  value : String
}

///|
priv struct SavedStyle {
  value : String
  priority : String
}

///|
priv struct DiagramSize {
  width : Double
  height : Double
}

///|
priv struct DiagramBodyCursorCoordinator {
  document : @rdom.Document
  mut active : Bool
}

///|
priv struct DiagramBodyCursorLease {
  coordinator : DiagramBodyCursorCoordinator
  body : @rdom.Element
  saved_cursor : SavedStyle
  mut active : Bool
}

///|
let diagram_body_cursor_coordinators : Array[DiagramBodyCursorCoordinator] = []

///|
priv struct MarkdownDiagramViewport {
  wrapper : @rdom.Element
  content : @rdom.Element
  svg : @rdom.Element
  controls : @rdom.Element
  pan_button : @rdom.Element
  zoom_out_button : @rdom.Element
  zoom_in_button : @rdom.Element
  fit_button : @rdom.Element
  resize_handle : @rdom.Element
  owner_document : @rdom.Document
  owner_window : @rdom.Window
  saved_tabindex : SavedAttribute
  saved_aria_label : SavedAttribute
  saved_height : SavedStyle
  saved_overflow : SavedStyle
  saved_cursor : SavedStyle
  on_size_changed : () -> Unit
  listeners : Array[@base_common.Disposable]
  mut observer : @base_common.Disposable?
  mut pending_frame : (() -> Unit)?
  mut body_cursor_lease : DiagramBodyCursorLease?
  mut active : Bool
  mut initialized : Bool
  mut scale : Double
  mut fit_scale : Double
  mut translate_x : Double
  mut translate_y : Double
  mut last_svg_width : Double
  mut last_svg_height : Double
  mut custom_height : Double?
  mut has_interacted : Bool
  mut pan_mode_enabled : Bool
  mut is_panning : Bool
  mut has_dragged : Bool
  mut pan_pointer_id : Int?
  mut start_x : Double
  mut start_y : Double
  mut previous_move_x : Double
  mut previous_move_y : Double
  mut is_resizing : Bool
  mut resize_pointer_id : Int?
  mut resize_start_y : Double
  mut resize_start_height : Double
}

///|
priv struct MarkdownDiagramViewportLifetime {
  target : @rdom.Element
  on_size_changed : () -> Unit
  schedule_frame : (() -> Unit) -> () -> Unit
  controllers : Array[MarkdownDiagramViewport]
  mut active : Bool
}

///|
priv enum DiagramViewportMountResult {
  Mounted(MarkdownDiagramViewport)
  Skipped
  Failed
}

///|
/// Owns the interactive diagram viewports mounted in one rendered Markdown
/// root. Successful direct Diago, UML, and Mermaid SVG children are enhanced. The
/// caller retains ownership of the target and disposes this handle before
/// replacing or removing that target.
struct DiagramViewports {
  lifetime : MarkdownDiagramViewportLifetime
}

///|
/// Synchronously mounts controls and resize handles for every matching direct
/// Diago, UML, or Mermaid SVG. Geometry is initialized at the next
/// animation-frame boundary. Call `refresh` after an asynchronous renderer
/// commits or replaces a direct SVG.
/// `on_size_changed` invalidates the owning presentation whenever this
/// component writes a new inline viewport height.
///
/// ```d2
/// direction: right
///
/// group: viewport group
/// controller: one controller per Diago, UML, or Mermaid SVG
/// wrapper: borrowed wrapper and SVG
/// hooks: pointer, wheel, resize hooks
/// cursor: body-cursor lease
/// callback: presentation measurement callback
///
/// group -> controller: owns many
/// controller -> wrapper: temporarily enhances
/// controller -> hooks: owns
/// controller -> cursor: while resizing
/// controller -> callback: inline height changed
/// ```
///
/// Disposal walks the owned controllers in reverse and restores every borrowed
/// wrapper attribute and inline style before the caller replaces the target.
pub fn DiagramViewports::DiagramViewports(
  target : @rdom.Element,
  on_size_changed : () -> Unit,
) -> DiagramViewports {
  let schedule_frame = (callback : () -> Unit) => {
    let registration = @base_browser.schedule_at_next_animation_frame(callback)
    () => registration.dispose()
  }
  let lifetime : MarkdownDiagramViewportLifetime = {
    target,
    on_size_changed,
    schedule_frame,
    controllers: [],
    active: true,
  }
  lifetime.refresh()
  { lifetime, }
}

///|
/// Reconciles asynchronously committed or replaced Mermaid SVGs with their
/// interactive viewport controllers. Existing current controllers retain
/// their interaction state; stale controllers are disposed before replacement
/// SVGs are mounted.
pub fn DiagramViewports::refresh(self : DiagramViewports) -> Unit {
  self.lifetime.refresh()
}

///|
fn MarkdownDiagramViewportLifetime::refresh(
  self : MarkdownDiagramViewportLifetime,
) -> Unit {
  if !self.active {
    return
  }
  for index in (self.controllers.length() - 1)>=..0 {
    let controller = self.controllers[index]
    if !controller.is_current(self.target) {
      self.controllers.remove(index) |> ignore
      controller.dispose()
    }
  }
  let candidates : Array[@rdom.Element] = []
  collect_diagram_viewport_candidates(self.target, candidates)
  for candidate in candidates {
    if !self.active {
      break
    }
    match
      mount_diagram_viewport(
        candidate,
        self.target,
        self.on_size_changed,
        self.schedule_frame,
      ) {
      Mounted(controller) => self.controllers.push(controller)
      Skipped => ()
      Failed => self.dispose()
    }
  }
}

///|
/// Idempotently releases every viewport listener, observer, animation frame,
/// owning-window drag, temporary cursor, and DOM reference.
pub fn DiagramViewports::dispose(self : DiagramViewports) -> Unit {
  self.lifetime.dispose()
}

///|
fn MarkdownDiagramViewportLifetime::dispose(
  self : MarkdownDiagramViewportLifetime,
) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  while self.controllers.pop() is Some(controller) {
    controller.dispose()
  }
}

///|
fn collect_diagram_viewport_candidates(
  root : @rdom.Element,
  candidates : Array[@rdom.Element],
) -> Unit {
  for child in root.get_children() {
    let language = element_attribute_or_empty(child, "data-diagram-language")
    if element_has_class(child, "moonbit-viewer-markdown-diagram") {
      if (language == "diago" || language == "uml" || language == "mermaid") &&
        !element_has_class(child, diagram_viewport_class) &&
        direct_svg_child(child) is Some(_) {
        candidates.push(child)
      }
      // A diagram wrapper owns one direct SVG. Treat it as a scan boundary so
      // transcript refreshes never walk the generated SVG or injected controls.
    } else {
      collect_diagram_viewport_candidates(child, candidates)
    }
  }
}

///|
fn direct_svg_child(wrapper : @rdom.Element) -> @rdom.Element? {
  for child in wrapper.get_children() {
    let name = child.get_node_name()
    if name == "svg" || name == "SVG" {
      return Some(child)
    }
  }
  None
}

///|
fn mount_diagram_viewport(
  wrapper : @rdom.Element,
  fallback_target : @rdom.Element,
  on_size_changed : () -> Unit,
  schedule_frame : (() -> Unit) -> () -> Unit,
) -> DiagramViewportMountResult {
  guard direct_svg_child(wrapper) is Some(svg) else { return Skipped }
  let result : Ref[DiagramViewportMountResult] = Ref(Skipped)
  let found = with_diagram_viewport_environment(wrapper, fallback_target, (
    owner_document,
    owner_window,
  ) => {
    result.val = mount_diagram_viewport_in_environment(
      wrapper, svg, owner_document, owner_window, on_size_changed, schedule_frame,
    )
  })
  if found {
    result.val
  } else {
    Skipped
  }
}

///|
fn mount_diagram_viewport_in_environment(
  wrapper : @rdom.Element,
  svg : @rdom.Element,
  owner_document : @rdom.Document,
  owner_window : @rdom.Window,
  on_size_changed : () -> Unit,
  schedule_frame : (() -> Unit) -> () -> Unit,
) -> DiagramViewportMountResult {
  let content = owner_document.create_element("div")
  content.set_attribute("class", diagram_content_class)
  let controls = owner_document.create_element("div")
  controls.set_attribute("class", diagram_controls_class)
  controls.set_attribute("role", "toolbar")
  let language = element_attribute_or_empty(wrapper, "data-diagram-language")
  let diagram_name = match language {
    "mermaid" => "Mermaid"
    "uml" => "UML"
    _ => "D2"
  }
  controls.set_attribute("aria-label", "\{diagram_name} diagram controls")
  let pan_button = create_diagram_button(
    owner_document,
    "moonbit-viewer-markdown-diagram-pan",
    "Toggle pan mode",
    "codicon-move",
    pressed=false,
  )
  let zoom_out_button = create_diagram_button(
    owner_document, "moonbit-viewer-markdown-diagram-zoom-out", "Zoom out", "codicon-zoom-out",
  )
  let zoom_in_button = create_diagram_button(
    owner_document, "moonbit-viewer-markdown-diagram-zoom-in", "Zoom in", "codicon-zoom-in",
  )
  let fit_button = create_diagram_button(
    owner_document, "moonbit-viewer-markdown-diagram-fit", "Fit diagram", "codicon-screen-normal",
  )
  controls.append_child(pan_button.as_node())
  controls.append_child(zoom_out_button.as_node())
  controls.append_child(zoom_in_button.as_node())
  controls.append_child(fit_button.as_node())
  let resize_handle = owner_document.create_element("div")
  resize_handle.set_attribute("class", diagram_resize_handle_class)
  resize_handle.set_attribute("title", "Drag to resize")
  resize_handle.set_attribute("tabindex", "0")
  resize_handle.set_attribute("role", "separator")
  resize_handle.set_attribute("aria-label", "Resize diagram")
  resize_handle.set_attribute("aria-orientation", "horizontal")
  let controller : MarkdownDiagramViewport = {
    wrapper,
    content,
    svg,
    controls,
    pan_button,
    zoom_out_button,
    zoom_in_button,
    fit_button,
    resize_handle,
    owner_document,
    owner_window,
    saved_tabindex: save_element_attribute(wrapper, "tabindex"),
    saved_aria_label: save_element_attribute(wrapper, "aria-label"),
    saved_height: save_element_style(wrapper, "height"),
    saved_overflow: save_element_style(wrapper, "overflow"),
    saved_cursor: save_element_style(wrapper, "cursor"),
    on_size_changed,
    listeners: [],
    observer: None,
    pending_frame: None,
    body_cursor_lease: None,
    active: true,
    initialized: false,
    scale: 1.0,
    fit_scale: 1.0,
    translate_x: 0.0,
    translate_y: 0.0,
    last_svg_width: 0.0,
    last_svg_height: 0.0,
    custom_height: None,
    has_interacted: false,
    pan_mode_enabled: false,
    is_panning: false,
    has_dragged: false,
    pan_pointer_id: None,
    start_x: 0.0,
    start_y: 0.0,
    previous_move_x: 0.0,
    previous_move_y: 0.0,
    is_resizing: false,
    resize_pointer_id: None,
    resize_start_y: 0.0,
    resize_start_height: 0.0,
  }
  add_element_class(wrapper, diagram_viewport_class)
  wrapper.set_attribute("tabindex", "0")
  wrapper.set_attribute(
    "aria-label",
    match language {
      "mermaid" => "Interactive Mermaid diagram"
      "uml" => "Interactive UML diagram"
      _ => "Interactive Diago diagram"
    },
  )
  @base_browser.set_style_property(wrapper, "overflow", "hidden")
  @base_browser.set_style_property(content, "transform-origin", "0 0")
  wrapper.insert_before(
    content.as_node(),
    @js.Nullable::from_option(Some(svg.as_node())),
  )
  content.append_child(svg.as_node())
  wrapper.append_child(controls.as_node())
  wrapper.append_child(resize_handle.as_node())
  controller.install_listeners()
  controller.observer = @base_browser.observe_element_resize(wrapper, () => {
    if controller.active {
      controller.layout() |> ignore
    }
  })
  if controller.observer is None {
    controller.dispose()
    return Failed
  }
  let frame_pending = Ref(true)
  let cancel_frame = schedule_frame(() => {
    frame_pending.val = false
    controller.pending_frame = None
    if controller.active {
      controller.layout() |> ignore
    }
  })
  if frame_pending.val {
    controller.pending_frame = Some(cancel_frame)
  } else {
    cancel_frame()
  }
  controller.set_cursor(false, false)
  Mounted(controller)
}

///|
fn create_diagram_button(
  document : @rdom.Document,
  class_name : String,
  label : String,
  icon_class : String,
  pressed? : Bool,
) -> @rdom.Element {
  let button = document.create_element("button")
  button.set_attribute("class", class_name)
  button.set_attribute("type", "button")
  button.set_attribute("title", label)
  button.set_attribute("aria-label", label)
  match pressed {
    Some(value) =>
      button.set_attribute("aria-pressed", if value { "true" } else { "false" })
    None => ()
  }
  let icon = document.create_element("span")
  icon.set_attribute("class", "codicon \{icon_class}")
  icon.set_attribute("aria-hidden", "true")
  button.append_child(icon.as_node())
  button
}

///|
fn MarkdownDiagramViewport::install_listeners(
  self : MarkdownDiagramViewport,
) -> Unit {
  let consume_control_pointer = (event : @rdom.Event) => {
    event.stop_propagation()
  }
  for
    button in [
      self.pan_button,
      self.zoom_out_button,
      self.zoom_in_button,
      self.fit_button,
    ] {
    self.listen(
      button.as_event_target(),
      "pointerdown",
      consume_control_pointer,
    )
    self.listen(button.as_event_target(), "mousedown", consume_control_pointer)
  }
  self.listen(self.pan_button.as_event_target(), "click", event => {
    event.prevent_default()
    event.stop_propagation()
    self.pan_mode_enabled = !self.pan_mode_enabled
    set_element_class_active(self.pan_button, "active", self.pan_mode_enabled)
    self.pan_button.set_attribute(
      "aria-pressed",
      if self.pan_mode_enabled {
        "true"
      } else {
        "false"
      },
    )
    self.set_cursor(false, false)
  })
  self.listen(self.zoom_out_button.as_event_target(), "click", event => {
    event.prevent_default()
    event.stop_propagation()
    self.zoom_at_center(0.8) |> ignore
  })
  self.listen(self.zoom_in_button.as_event_target(), "click", event => {
    event.prevent_default()
    event.stop_propagation()
    self.zoom_at_center(1.25) |> ignore
  })
  self.listen(self.fit_button.as_event_target(), "click", event => {
    event.prevent_default()
    event.stop_propagation()
    self.fit() |> ignore
  })
  self.listen(self.wrapper.as_event_target(), "pointerdown", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if !self.active ||
      self.is_panning ||
      self.is_resizing ||
      mouse.get_button() != 0 ||
      (!self.pan_mode_enabled && !mouse.get_alt_key()) {
      return
    }
    if !self.initialized && !self.center_natural_content() {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    self.is_panning = true
    self.has_dragged = false
    self.pan_pointer_id = Some(@base_browser.mouse_event_pointer_id(mouse))
    let client_x = Double::from_int(mouse.get_client_x())
    let client_y = Double::from_int(mouse.get_client_y())
    self.start_x = client_x - self.translate_x
    self.start_y = client_y - self.translate_y
    self.previous_move_x = client_x
    self.previous_move_y = client_y
    @base_browser.set_style_property(self.wrapper, "cursor", "grabbing")
  })
  self.listen(self.wrapper.as_event_target(), "pointermove", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if self.active && !self.is_panning {
      self.set_cursor(mouse.get_alt_key(), mouse.get_shift_key())
    }
  })
  self.listen(self.wrapper.as_event_target(), "click", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if !self.active || !mouse.get_alt_key() || self.has_dragged {
      return
    }
    if !self.initialized && !self.center_natural_content() {
      return
    }
    let rect = self.viewport_rect()
    if !is_positive_finite(rect.get_width()) ||
      !is_positive_finite(rect.get_height()) {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    self.zoom_at_point(
      if mouse.get_shift_key() {
        0.8
      } else {
        1.25
      },
      Double::from_int(mouse.get_client_x()) - rect.get_left(),
      Double::from_int(mouse.get_client_y()) - rect.get_top(),
    )
    |> ignore
  })
  self.listen(
    self.wrapper.as_event_target(),
    "wheel",
    event => {
      guard event.to_wheel_event() is Some(wheel) else { return }
      if !self.active || (!wheel.get_ctrl_key() && !wheel.get_alt_key()) {
        return
      }
      if !self.initialized && !self.center_natural_content() {
        return
      }
      let rect = self.viewport_rect()
      let delta_y = wheel.get_delta_y()
      if !is_positive_finite(rect.get_width()) ||
        !is_positive_finite(rect.get_height()) ||
        !is_finite(delta_y) {
        return
      }
      event.prevent_default()
      event.stop_propagation()
      let multiplier = if wheel.get_ctrl_key() { 10.0 } else { 1.0 }
      let delta = -delta_y * diagram_zoom_factor * multiplier
      self.zoom_at_point(
        1.0 + delta,
        Double::from_int(wheel.get_client_x()) - rect.get_left(),
        Double::from_int(wheel.get_client_y()) - rect.get_top(),
      )
      |> ignore
    },
    passive_false=true,
  )
  self.listen(self.wrapper.as_event_target(), "pointerenter", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if !self.is_panning {
      self.set_cursor(mouse.get_alt_key(), mouse.get_shift_key())
    }
  })
  let handle_key_change = (event : @rdom.Event) => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    if (keyboard.key() == "Alt" || keyboard.key() == "Shift") &&
      !self.is_panning {
      event.prevent_default()
      self.set_cursor(keyboard.alt_key(), keyboard.shift_key())
    }
  }
  self.listen(self.owner_window.as_event_target(), "keydown", handle_key_change)
  self.listen(self.owner_window.as_event_target(), "keyup", handle_key_change)
  self.listen(self.owner_window.as_event_target(), "resize", _event => {
    if self.active {
      self.layout() |> ignore
    }
  })
  self.listen(self.resize_handle.as_event_target(), "pointerdown", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if !self.active ||
      self.is_resizing ||
      self.is_panning ||
      mouse.get_button() != 0 {
      return
    }
    if !self.initialized && !self.center_natural_content() {
      return
    }
    let rect = self.viewport_rect()
    if !is_positive_finite(rect.get_height()) {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    if !self.acquire_body_cursor() {
      return
    }
    self.is_resizing = true
    self.resize_pointer_id = Some(@base_browser.mouse_event_pointer_id(mouse))
    self.resize_start_y = Double::from_int(mouse.get_client_y())
    self.resize_start_height = rect.get_height()
  })
  self.listen(self.owner_window.as_event_target(), "pointermove", event => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    if !self.active {
      return
    }
    let pointer_id = @base_browser.mouse_event_pointer_id(mouse)
    if self.is_panning && self.pan_pointer_id == Some(pointer_id) {
      if mouse.get_buttons() == 0 {
        self.finish_pan(mouse)
        return
      }
      event.prevent_default()
      event.stop_propagation()
      let client_x = Double::from_int(mouse.get_client_x())
      let client_y = Double::from_int(mouse.get_client_y())
      let dx = client_x - self.previous_move_x
      let dy = client_y - self.previous_move_y
      if dx.abs() > diagram_drag_threshold || dy.abs() > diagram_drag_threshold {
        self.has_dragged = true
      }
      self.previous_move_x = client_x
      self.previous_move_y = client_y
      self.translate_x = client_x - self.start_x
      self.translate_y = client_y - self.start_y
      self.apply_transform()
      return
    }
    if self.is_resizing && self.resize_pointer_id == Some(pointer_id) {
      if mouse.get_buttons() == 0 {
        self.finish_resize()
        return
      }
      event.prevent_default()
      event.stop_propagation()
      self.resize_to_height(
        self.resize_start_height +
        Double::from_int(mouse.get_client_y()) -
        self.resize_start_y,
      )
      |> ignore
    }
  })
  let finish_pointer_gesture = (event : @rdom.Event) => {
    guard event.to_mouse_event() is Some(mouse) else { return }
    let pointer_id = @base_browser.mouse_event_pointer_id(mouse)
    if self.is_panning && self.pan_pointer_id == Some(pointer_id) {
      event.prevent_default()
      event.stop_propagation()
      self.finish_pan(mouse)
    }
    if self.is_resizing && self.resize_pointer_id == Some(pointer_id) {
      event.prevent_default()
      event.stop_propagation()
      self.finish_resize()
    }
  }
  self.listen(
    self.owner_window.as_event_target(),
    "pointerup",
    finish_pointer_gesture,
  )
  self.listen(
    self.owner_window.as_event_target(),
    "pointercancel",
    finish_pointer_gesture,
  )
  self.listen(self.resize_handle.as_event_target(), "keydown", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    if keyboard.key() != "ArrowUp" && keyboard.key() != "ArrowDown" {
      return
    }
    if !self.initialized && !self.center_natural_content() {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    let rect = self.viewport_rect()
    let current_height = match self.custom_height {
      Some(height) => height
      None =>
        if is_positive_finite(rect.get_height()) {
          rect.get_height()
        } else {
          diagram_minimum_height
        }
    }
    let direction = if keyboard.key() == "ArrowUp" { -1.0 } else { 1.0 }
    let step = if keyboard.shift_key() { 50.0 } else { 10.0 }
    self.resize_to_height(current_height + direction * step) |> ignore
  })
}

///|
fn MarkdownDiagramViewport::listen(
  self : MarkdownDiagramViewport,
  target : @rdom.EventTarget,
  event_type : String,
  listener : @rdom.Listener,
  passive_false? : Bool = false,
) -> Unit {
  if passive_false {
    add_non_passive_event_listener(target, event_type, listener)
  } else {
    target.add_event_listener(event_type, listener)
  }
  self.listeners.push(
    @base_common.Disposable::from(() => {
      if passive_false {
        remove_non_passive_event_listener(target, event_type, listener)
      } else {
        target.remove_event_listener(event_type, listener)
      }
    }),
  )
}

///|
fn MarkdownDiagramViewport::viewport_rect(
  self : MarkdownDiagramViewport,
) -> @rdom.DOMRect {
  self.wrapper.get_bounding_client_rect()
}

///|
fn MarkdownDiagramViewport::measure_svg(
  self : MarkdownDiagramViewport,
) -> DiagramSize? {
  let saved_transform = save_element_style(self.content, "transform")
  @base_browser.set_style_property(self.content, "transform", "none")
  defer restore_element_style(self.content, "transform", saved_transform)
  let rect = self.svg.get_bounding_client_rect()
  if !is_positive_finite(rect.get_width()) ||
    !is_positive_finite(rect.get_height()) {
    return None
  }
  Some({ width: rect.get_width(), height: rect.get_height(), })
}

///|
fn MarkdownDiagramViewport::apply_transform(
  self : MarkdownDiagramViewport,
) -> Unit {
  @base_browser.set_style_property(
    self.content,
    "transform",
    "translate(\{self.translate_x}px, \{self.translate_y}px) scale(\{self.scale})",
  )
}

///|
fn MarkdownDiagramViewport::write_height(
  self : MarkdownDiagramViewport,
  height : Double,
) -> Bool {
  if !is_positive_finite(height) {
    return false
  }
  let css_height = "\{height}px"
  if @base_browser.element_style_value(self.wrapper, "height") == css_height {
    return false
  }
  @base_browser.set_style_property(self.wrapper, "height", css_height)
  if self.active {
    (self.on_size_changed)()
  }
  true
}

///|
fn MarkdownDiagramViewport::set_cursor(
  self : MarkdownDiagramViewport,
  alt_key : Bool,
  shift_key : Bool,
) -> Unit {
  if !self.active {
    return
  }
  let cursor = if self.pan_mode_enabled {
    "grab"
  } else if alt_key && shift_key {
    "zoom-out"
  } else if alt_key {
    "grab"
  } else {
    "default"
  }
  @base_browser.set_style_property(self.wrapper, "cursor", cursor)
}

///|
fn MarkdownDiagramViewport::height_for_svg(
  self : MarkdownDiagramViewport,
  svg_size : DiagramSize,
) -> Double {
  match self.custom_height {
    Some(height) => height
    None => {
      let window_height = diagram_window_inner_height(self.owner_window)
      let initial_height_limit = if is_positive_finite(window_height) {
        diagram_maximum_initial_height.min(
          window_height * diagram_initial_window_height_ratio,
        )
      } else {
        diagram_maximum_initial_height
      }
      svg_size.height.min(initial_height_limit)
    }
  }
}

///|
fn MarkdownDiagramViewport::fit_content_to_rect(
  self : MarkdownDiagramViewport,
  svg_size : DiagramSize,
  rect : @rdom.DOMRect,
) -> Bool {
  let available_width = 1.0.max(rect.get_width() - diagram_fit_padding * 2.0)
  let available_height = 1.0.max(rect.get_height() - diagram_fit_padding * 2.0)
  let next_scale = 1.0
    .min(available_width / svg_size.width)
    .min(available_height / svg_size.height)
  if !is_positive_finite(next_scale) {
    return false
  }
  let next_x = (rect.get_width() - svg_size.width * next_scale) / 2.0
  let next_y = (rect.get_height() - svg_size.height * next_scale) / 2.0
  if !is_finite(next_x) || !is_finite(next_y) {
    return false
  }
  self.scale = next_scale
  self.fit_scale = next_scale
  self.translate_x = next_x
  self.translate_y = next_y
  self.last_svg_width = svg_size.width
  self.last_svg_height = svg_size.height
  self.apply_transform()
  true
}

///|
fn MarkdownDiagramViewport::center_natural_content(
  self : MarkdownDiagramViewport,
) -> Bool {
  guard self.measure_svg() is Some(svg_size) else { return false }
  let before = self.viewport_rect()
  if !is_positive_finite(before.get_width()) {
    return false
  }
  let height = self.height_for_svg(svg_size)
  if !is_positive_finite(height) {
    return false
  }
  self.write_height(height) |> ignore
  let rect = self.viewport_rect()
  if !is_positive_finite(rect.get_width()) ||
    !is_positive_finite(rect.get_height()) {
    return false
  }
  let fits_initial_height = match self.custom_height {
    Some(_) => false
    None => height < svg_size.height
  }
  if fits_initial_height {
    if !self.fit_content_to_rect(svg_size, rect) {
      return false
    }
  } else {
    self.last_svg_width = svg_size.width
    self.last_svg_height = svg_size.height
    self.scale = 1.0
    self.fit_scale = 1.0
    self.translate_x = (rect.get_width() - svg_size.width) / 2.0
    self.translate_y = 0.0
    self.apply_transform()
  }
  self.initialized = true
  true
}

///|
fn MarkdownDiagramViewport::preserve_visible_origin(
  self : MarkdownDiagramViewport,
) -> Bool {
  if !is_positive_finite(self.scale) {
    return false
  }
  let origin_x = -self.translate_x / self.scale
  let origin_y = -self.translate_y / self.scale
  let percent_x = if self.last_svg_width > 0.0 {
    origin_x / self.last_svg_width
  } else {
    0.0
  }
  let percent_y = if self.last_svg_height > 0.0 {
    origin_y / self.last_svg_height
  } else {
    0.0
  }
  guard self.measure_svg() is Some(svg_size) else { return false }
  let height = self.height_for_svg(svg_size)
  if !is_positive_finite(height) {
    return false
  }
  self.write_height(height) |> ignore
  let rect = self.viewport_rect()
  if !is_positive_finite(rect.get_width()) ||
    !is_positive_finite(rect.get_height()) {
    return false
  }
  self.last_svg_width = svg_size.width
  self.last_svg_height = svg_size.height
  self.translate_x = -(percent_x * svg_size.width) * self.scale
  self.translate_y = -(percent_y * svg_size.height) * self.scale
  self.apply_transform()
  true
}

///|
fn MarkdownDiagramViewport::layout(self : MarkdownDiagramViewport) -> Bool {
  if !self.active {
    return false
  }
  if !self.initialized {
    return self.center_natural_content()
  }
  if self.has_interacted {
    self.preserve_visible_origin()
  } else {
    self.center_natural_content()
  }
}

///|
fn MarkdownDiagramViewport::zoom_at_point(
  self : MarkdownDiagramViewport,
  factor : Double,
  x : Double,
  y : Double,
) -> Bool {
  if !self.initialized && !self.center_natural_content() {
    return false
  }
  if !is_finite(factor) ||
    !is_finite(x) ||
    !is_finite(y) ||
    !is_positive_finite(self.scale) {
    return false
  }
  let min_allowed_scale = diagram_min_scale.min(self.fit_scale).min(self.scale)
  let new_scale = (self.scale * factor)
    .max(min_allowed_scale)
    .min(diagram_max_scale)
  if !is_positive_finite(new_scale) {
    return false
  }
  let scale_factor = new_scale / self.scale
  self.translate_x = x - (x - self.translate_x) * scale_factor
  self.translate_y = y - (y - self.translate_y) * scale_factor
  self.scale = new_scale
  self.has_interacted = true
  self.apply_transform()
  true
}

///|
fn MarkdownDiagramViewport::zoom_at_center(
  self : MarkdownDiagramViewport,
  factor : Double,
) -> Bool {
  if !self.initialized && !self.center_natural_content() {
    return false
  }
  let rect = self.viewport_rect()
  if !is_positive_finite(rect.get_width()) ||
    !is_positive_finite(rect.get_height()) {
    return false
  }
  self.zoom_at_point(factor, rect.get_width() / 2.0, rect.get_height() / 2.0)
}

///|
fn MarkdownDiagramViewport::fit(self : MarkdownDiagramViewport) -> Bool {
  if !self.initialized && !self.center_natural_content() {
    return false
  }
  guard self.measure_svg() is Some(svg_size) else { return false }
  let rect = self.viewport_rect()
  if !is_positive_finite(rect.get_width()) ||
    !is_positive_finite(rect.get_height()) {
    return false
  }
  if !self.fit_content_to_rect(svg_size, rect) {
    return false
  }
  self.initialized = true
  self.has_interacted = true
  true
}

///|
fn MarkdownDiagramViewport::resize_to_height(
  self : MarkdownDiagramViewport,
  height : Double,
) -> Bool {
  if !is_finite(height) {
    return false
  }
  let next_height = diagram_minimum_height.max(height)
  self.custom_height = Some(next_height)
  self.write_height(next_height) |> ignore
  true
}

///|
fn MarkdownDiagramViewport::acquire_body_cursor(
  self : MarkdownDiagramViewport,
) -> Bool {
  if self.body_cursor_lease is Some(_) {
    return false
  }
  let acquired = Ref(false)
  with_document_body(self.owner_document, body => {
    let coordinator = body_cursor_coordinator_for(self.owner_document)
    if coordinator.active {
      return
    }
    coordinator.active = true
    let lease : DiagramBodyCursorLease = {
      coordinator,
      body,
      saved_cursor: save_element_style(body, "cursor"),
      active: true,
    }
    @base_browser.set_style_property(body, "cursor", "ns-resize")
    self.body_cursor_lease = Some(lease)
    acquired.val = true
  })
  |> ignore
  acquired.val
}

///|
fn MarkdownDiagramViewport::restore_body_cursor(
  self : MarkdownDiagramViewport,
) -> Unit {
  match self.body_cursor_lease {
    Some(lease) => release_body_cursor_lease(lease)
    None => ()
  }
  self.body_cursor_lease = None
}

///|
fn MarkdownDiagramViewport::finish_pan(
  self : MarkdownDiagramViewport,
  event : @rdom.MouseEvent,
) -> Unit {
  if !self.is_panning {
    return
  }
  self.is_panning = false
  self.has_interacted = true
  self.pan_pointer_id = None
  self.set_cursor(event.get_alt_key(), event.get_shift_key())
}

///|
fn MarkdownDiagramViewport::finish_resize(
  self : MarkdownDiagramViewport,
) -> Unit {
  if !self.is_resizing {
    return
  }
  self.is_resizing = false
  self.resize_pointer_id = None
  self.restore_body_cursor()
}

///|
fn MarkdownDiagramViewport::is_current(
  self : MarkdownDiagramViewport,
  target : @rdom.Element,
) -> Bool {
  // Keyed hosts may detach a complete diagram row without disturbing the
  // wrapper/content/SVG relationship inside that subtree. Target containment
  // is therefore part of ownership, not merely a structural sanity check.
  guard self.active &&
    target.contains(self.wrapper.as_node()) &&
    element_has_class(self.wrapper, diagram_viewport_class) else {
    return false
  }
  guard self.content.get_parent_node().to_option() is Some(content_parent) &&
    content_parent.is_same_node(self.wrapper.as_node()) else {
    return false
  }
  match self.svg.get_parent_node().to_option() {
    Some(svg_parent) => svg_parent.is_same_node(self.content.as_node())
    None => false
  }
}

///|
fn MarkdownDiagramViewport::dispose(self : MarkdownDiagramViewport) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  if self.pending_frame is Some(cancel) {
    cancel()
  }
  self.pending_frame = None
  if self.observer is Some(observer) {
    observer.dispose()
  }
  self.observer = None
  self.finish_resize()
  self.is_panning = false
  self.pan_pointer_id = None
  while self.listeners.pop() is Some(listener) {
    listener.dispose()
  }
  @base_browser.remove_element(self.controls)
  @base_browser.remove_element(self.resize_handle)
  match self.content.get_parent_node().to_option() {
    Some(parent) =>
      if parent.is_same_node(self.wrapper.as_node()) {
        self.wrapper.insert_before(
          self.svg.as_node(),
          @js.Nullable::from_option(Some(self.content.as_node())),
        )
        @base_browser.remove_element(self.content)
      }
    None => ()
  }
  remove_element_class(self.wrapper, diagram_viewport_class)
  restore_element_attribute(self.wrapper, "tabindex", self.saved_tabindex)
  restore_element_attribute(self.wrapper, "aria-label", self.saved_aria_label)
  restore_element_style(self.wrapper, "height", self.saved_height)
  restore_element_style(self.wrapper, "overflow", self.saved_overflow)
  restore_element_style(self.wrapper, "cursor", self.saved_cursor)
}

///|
fn body_cursor_coordinator_for(
  document : @rdom.Document,
) -> DiagramBodyCursorCoordinator {
  for coordinator in diagram_body_cursor_coordinators {
    if same_document(coordinator.document, document) {
      return coordinator
    }
  }
  let coordinator : DiagramBodyCursorCoordinator = { document, active: false, }
  diagram_body_cursor_coordinators.push(coordinator)
  coordinator
}

///|
fn release_body_cursor_lease(lease : DiagramBodyCursorLease) -> Unit {
  if !lease.active {
    return
  }
  lease.active = false
  restore_element_style(lease.body, "cursor", lease.saved_cursor)
  lease.coordinator.active = false
  diagram_body_cursor_coordinators.retain(coordinator => {
    coordinator.active ||
    !same_document(coordinator.document, lease.coordinator.document)
  })
}

///|
fn is_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn is_positive_finite(value : Double) -> Bool {
  is_finite(value) && value > 0.0
}

///|
fn element_class_tokens(element : @rdom.Element) -> Array[String] {
  [
    for token in element_attribute_or_empty(element, "class").split(" ") if !token.is_empty() => {
      token.to_owned()
    }
  ]
}

///|
fn element_has_class(element : @rdom.Element, class_name : String) -> Bool {
  element_class_tokens(element).contains(class_name)
}

///|
fn add_element_class(element : @rdom.Element, class_name : String) -> Unit {
  if element_has_class(element, class_name) {
    return
  }
  let tokens = element_class_tokens(element)
  tokens.push(class_name)
  element.set_attribute("class", tokens.join(" "))
}

///|
fn remove_element_class(element : @rdom.Element, class_name : String) -> Unit {
  element.set_attribute(
    "class",
    element_class_tokens(element).filter(token => token != class_name).join(" "),
  )
}

///|
fn set_element_class_active(
  element : @rdom.Element,
  class_name : String,
  active : Bool,
) -> Unit {
  if active {
    add_element_class(element, class_name)
  } else {
    remove_element_class(element, class_name)
  }
}

///|
fn save_element_attribute(
  element : @rdom.Element,
  name : String,
) -> SavedAttribute {
  {
    present: element_has_attribute(element, name),
    value: element_attribute_or_empty(element, name),
  }
}

///|
fn restore_element_attribute(
  element : @rdom.Element,
  name : String,
  saved : SavedAttribute,
) -> Unit {
  if saved.present {
    element.set_attribute(name, saved.value)
  } else {
    element.remove_attribute(name)
  }
}

///|
fn save_element_style(element : @rdom.Element, name : String) -> SavedStyle {
  {
    value: @base_browser.element_style_value(element, name),
    priority: @base_browser.element_style_priority(element, name),
  }
}

///|
fn restore_element_style(
  element : @rdom.Element,
  name : String,
  saved : SavedStyle,
) -> Unit {
  if saved.value == "" {
    @base_browser.remove_style_property(element, name)
  } else if saved.priority == "" {
    @base_browser.set_style_property(element, name, saved.value)
  } else {
    @base_browser.set_style_property_with_priority(
      element,
      name,
      saved.value,
      saved.priority,
    )
  }
}

///|
/// `ownerDocument` and `defaultView` are not exposed by the vendored Rabbita
/// DOM bindings. The callback keeps nullable browser values out of MoonBit.
extern "js" fn with_diagram_viewport_environment(
  wrapper : @rdom.Element,
  fallback_target : @rdom.Element,
  callback : (@rdom.Document, @rdom.Window) -> Unit,
) -> Bool =
  #| (wrapper, fallbackTarget, callback) => {
  #|   const document = wrapper?.ownerDocument ?? fallbackTarget?.ownerDocument;
  #|   const window = document?.defaultView;
  #|   if (!document || !window) return false;
  #|   callback(document, window);
  #|   return true;
  #| }

///|
extern "js" fn diagram_window_inner_height(window : @rdom.Window) -> Double = "window => Number(window?.innerHeight)"

///|
/// Rabbita does not currently expose `hasAttribute` or nullable attribute
/// reads; these two bindings normalize that narrow DOM seam.
extern "js" fn element_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool = "(element, name) => element?.hasAttribute?.(name) === true"

///|
extern "js" fn element_attribute_or_empty(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element?.getAttribute?.(name) ?? ''"

///|
/// `Document.body` is not exposed by the current Rabbita DOM bindings. The
/// coordinator and lease themselves remain MoonBit-owned.
extern "js" fn with_document_body(
  document : @rdom.Document,
  callback : (@rdom.Element) -> Unit,
) -> Bool =
  #| (document, callback) => {
  #|   const body = document?.body;
  #|   if (!body) return false;
  #|   callback(body);
  #|   return true;
  #| }

///|
extern "js" fn same_document(
  left : @rdom.Document,
  right : @rdom.Document,
) -> Bool = "(left, right) => left === right"

///|
/// Wheel zoom must be non-passive so it can suppress browser scrolling after
/// a modifier gesture has been accepted.
extern "js" fn add_non_passive_event_listener(
  target : @rdom.EventTarget,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit =
  #| (target, eventType, listener) => {
  #|   target.addEventListener(eventType, listener, { passive: false });
  #| }

///|
extern "js" fn remove_non_passive_event_listener(
  target : @rdom.EventTarget,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit =
  #| (target, eventType, listener) => {
  #|   target.removeEventListener(eventType, listener, { passive: false });
  #| }
