// The inline "Add Feedback" input, porting `AgentFeedbackInputWidget`
// (`vscode/src/vs/sessions/contrib/agentFeedback/browser/
// agentFeedbackEditorInputContribution.ts:44-242`): a floating overlay node
// with an auto-growing textarea and review-style Cancel/Add actions. The
// primary action swaps Add ↔ Add-and-Submit while Alt is held
// (upstream's `ModifierKeyEmitter` swap, driven here from the textarea's own
// keydown/keyup since the widget owns the focus while typing). The widget is
// a null-position overlay widget: the glue positions it by writing
// `top`/`left` (`setPosition` → `layoutOverlayWidget` upstream). Keyboard is
// handled on the textarea directly (Shift+Enter inserts a newline, Enter adds,
// Alt+Enter adds and submits, Escape cancels). The editor-keydown steal and
// `Ctrl+I` focus routing of the upstream contribution go through the viewer's
// keybinding registry instead. Dropped: the ActionBar/keybinding-label chrome
// and the readonly-editor typing capture.

///|
/// `_MIN_WIDTH` / `_MAX_WIDTH` / `_MAX_WIDTH_EDITOR_FRACTION`.
let input_min_width_px : Double = 280.0

///|
let input_default_width_px : Double = 360.0

///|
let input_max_width_px : Double = 400.0

///|
let input_max_width_editor_fraction : Double = 0.9

///|
let input_min_height_px : Double = 64.0

///|
let input_max_height_px : Double = 180.0

///|
/// The glue-facing seam: submit/cancel routing plus the geometry reads the
/// widget needs while sizing (the upstream widget reached back into
/// `ICodeEditor.getLayoutInfo` for these).
pub(all) struct AgentFeedbackInputWidgetHost {
  /// Enter — `onDidTriggerAdd`.
  on_add : () -> Unit
  /// Alt+Enter — `onDidTriggerAddAndSubmit`.
  on_add_and_submit : () -> Unit
  /// Escape inside the textarea — the contribution hides and refocuses.
  on_cancel : () -> Unit
  /// The textarea grew/shrank; the glue repositions the widget
  /// (`this._updatePosition()` on `input`).
  on_layout : () -> Unit
  /// Focus left the textarea with no draft text; the glue auto-hides.
  on_blur_empty : () -> Unit
  /// `_computeMaxWidth`'s editor content width (layout width − content left).
  content_width : () -> Double
}

///|
struct AgentFeedbackInputWidget {
  host : AgentFeedbackInputWidgetHost
  root : @rdom.Element
  textarea : @rdom.Element
  cancel : @rdom.Element
  action : @rdom.Element
  mut showing_alt : Bool
}

///|
pub fn AgentFeedbackInputWidget::AgentFeedbackInputWidget(
  host : AgentFeedbackInputWidgetHost,
) -> AgentFeedbackInputWidget {
  let document = @rdom.document()
  let root = document.create_element("div")
  root.set_attribute("class", "agent-feedback-input-widget")
  root.set_attribute("style", "display:none")
  let textarea = document.create_element("textarea")
  textarea.set_attribute("rows", "3")
  textarea.set_attribute("placeholder", "Add feedback")
  textarea.set_attribute("aria-label", "Feedback")
  textarea.set_attribute("data-agent-feedback-input", "true")
  root.append_child(textarea.as_node())
  let actions = document.create_element("div")
  actions.set_attribute("class", "agent-feedback-input-actions")
  let cancel = document.create_element("button")
  cancel.set_attribute("type", "button")
  cancel.set_attribute(
    "class", "agent-feedback-input-action agent-feedback-input-action-cancel",
  )
  cancel.set_attribute("title", "Cancel feedback (Escape)")
  cancel.set_inner_html("Cancel")
  let action = document.create_element("button")
  action.set_attribute("type", "button")
  action.set_attribute("data-agent-feedback-action", "add")
  actions.append_child(cancel.as_node())
  actions.append_child(action.as_node())
  root.append_child(actions.as_node())
  let widget : AgentFeedbackInputWidget = {
    host,
    root,
    textarea,
    cancel,
    action,
    showing_alt: false,
  }
  widget.render_action()
  widget.hook_events()
  widget
}

///|
pub fn AgentFeedbackInputWidget::get_dom_node(
  self : AgentFeedbackInputWidget,
) -> @rdom.Element {
  self.root
}

///|
/// `_updateActionForAlt`: the primary button's label/title swap between Add
/// and Add-and-Submit with the Alt key.
fn AgentFeedbackInputWidget::render_action(
  self : AgentFeedbackInputWidget,
) -> Unit {
  if self.showing_alt {
    self.action.set_attribute(
      "class", "agent-feedback-input-action agent-feedback-input-action-primary agent-feedback-input-action-send",
    )
    self.action.set_attribute("title", "Add Feedback and Submit (Alt+Enter)")
    self.action.set_attribute("aria-label", "Add feedback and submit")
    self.action.set_inner_html("Add &amp; submit")
  } else {
    self.action.set_attribute(
      "class", "agent-feedback-input-action agent-feedback-input-action-primary agent-feedback-input-action-add",
    )
    self.action.set_attribute("title", "Add Feedback (Enter)")
    self.action.set_attribute("aria-label", "Add feedback")
    self.action.set_inner_html("Add feedback")
  }
  self.update_action_enabled()
}

///|
fn AgentFeedbackInputWidget::hook_events(
  self : AgentFeedbackInputWidget,
) -> Unit {
  // Containment (the comment widget precedent): interactions must not reach
  // the editor's root refocus / key handling.
  self.root.add_event_listener("mouseup", event => event.stop_propagation())
  self.root.add_event_listener("click", event => event.stop_propagation())
  self.root.add_event_listener("contextmenu", event => event.stop_propagation())
  // Mousedown anywhere on the widget that isn't the textarea itself focuses
  // the textarea (upstream's padding-click handler).
  self.root.add_event_listener("mousedown", event => {
    event.stop_propagation()
    if !input_event_targets(event, self.textarea) &&
      !input_event_targets(event, self.action) &&
      !input_event_targets(event, self.cancel) {
      event.prevent_default()
      @base_browser.focus_prevent_scroll(self.textarea)
    }
  })
  self.cancel.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    (self.host.on_cancel)()
  })
  self.action.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    if self.has_text() {
      if self.showing_alt {
        (self.host.on_add_and_submit)()
      } else {
        (self.host.on_add)()
      }
    }
  })
  self.textarea.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) => self.handle_keydown(event, keyboard)
      None => ()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("keyup", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        if self.showing_alt && !keyboard.alt_key() {
          self.showing_alt = false
          self.render_action()
        }
      None => ()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("input", _ => {
    self.auto_size()
    self.update_action_enabled()
    (self.host.on_layout)()
  })
  self.textarea.add_event_listener("blur", _ => {
    if !self.has_text() {
      (self.host.on_blur_empty)()
    }
  })
}

///|
fn AgentFeedbackInputWidget::handle_keydown(
  self : AgentFeedbackInputWidget,
  event : @rdom.Event,
  keyboard : @rdom.KeyboardEvent,
) -> Unit {
  if keyboard.alt_key() != self.showing_alt {
    self.showing_alt = keyboard.alt_key()
    self.render_action()
  }
  match keyboard.key() {
    "Escape" => {
      event.prevent_default()
      (self.host.on_cancel)()
    }
    "Enter" => {
      if keyboard.shift_key() {
        return
      }
      event.prevent_default()
      if !self.has_text() {
        return
      }
      if keyboard.alt_key() {
        (self.host.on_add_and_submit)()
      } else {
        (self.host.on_add)()
      }
    }
    _ => ()
  }
}

// --- glue-facing surface ---------------------------------------------------------

///|
pub fn AgentFeedbackInputWidget::show(self : AgentFeedbackInputWidget) -> Unit {
  @base_browser.set_style_property(self.root, "display", "")
}

///|
pub fn AgentFeedbackInputWidget::hide(self : AgentFeedbackInputWidget) -> Unit {
  @base_browser.set_style_property(self.root, "display", "none")
}

///|
/// Writes the overlay position (`setPosition` → the widget's absolute
/// `top`/`left` inside the `.overlayWidgets` container).
pub fn AgentFeedbackInputWidget::set_position(
  self : AgentFeedbackInputWidget,
  top : Double,
  left : Double,
) -> Unit {
  @base_browser.set_style_property(self.root, "top", "\{top.to_string()}px")
  @base_browser.set_style_property(self.root, "left", "\{left.to_string()}px")
}

///|
pub fn AgentFeedbackInputWidget::clear_input(
  self : AgentFeedbackInputWidget,
) -> Unit {
  input_set_textarea_value(self.textarea, "")
  self.update_action_enabled()
  self.auto_size()
}

///|
pub fn AgentFeedbackInputWidget::set_placeholder(
  self : AgentFeedbackInputWidget,
  placeholder : String,
) -> Unit {
  self.textarea.set_attribute("placeholder", placeholder)
  self.auto_size()
}

///|
pub fn AgentFeedbackInputWidget::focus_input(
  self : AgentFeedbackInputWidget,
) -> Unit {
  @base_browser.focus_prevent_scroll(self.textarea)
}

///|
pub fn AgentFeedbackInputWidget::value(
  self : AgentFeedbackInputWidget,
) -> String {
  input_textarea_value(self.textarea)
}

///|
/// Whether the textarea holds non-whitespace draft text — the upstream
/// `_hasInputText` freeze/auto-hide gate.
pub fn AgentFeedbackInputWidget::has_text(
  self : AgentFeedbackInputWidget,
) -> Bool {
  !is_blank(self.value())
}

///|
/// The rendered size, for the glue's flip/clamp positioning (upstream read
/// `offsetHeight`/`offsetWidth` with review-card-sized fallbacks).
pub fn AgentFeedbackInputWidget::measured_height(
  self : AgentFeedbackInputWidget,
) -> Double {
  let height = @base_browser.element_offset_height(self.root)
  if height > 0.0 {
    height
  } else {
    112.0
  }
}

///|
pub fn AgentFeedbackInputWidget::measured_width(
  self : AgentFeedbackInputWidget,
) -> Double {
  let width = @base_browser.element_offset_width(self.root)
  if width > 0.0 {
    width
  } else {
    input_default_width_px
  }
}

///|
fn AgentFeedbackInputWidget::update_action_enabled(
  self : AgentFeedbackInputWidget,
) -> Unit {
  if self.has_text() {
    self.action.remove_attribute("disabled")
  } else {
    self.action.set_attribute("disabled", "true")
  }
}

///|
/// `_autoSize`: keep a stable review-card width that never exceeds the editor
/// content area, and grow the textarea with its draft up to a practical cap.
fn AgentFeedbackInputWidget::auto_size(self : AgentFeedbackInputWidget) -> Unit {
  let max_width_cap = (self.host.content_width)() *
    input_max_width_editor_fraction
  let max_width = input_max_width_px.min(max_width_cap)
  let min_width = input_min_width_px.min(max_width)
  let width = input_default_width_px.min(max_width).max(min_width)
  @base_browser.set_style_property(self.root, "width", "\{width.to_string()}px")
  let height = input_textarea_grown_height(self.textarea)
  let clamped_height = height.max(input_min_height_px).min(input_max_height_px)
  @base_browser.set_style_property(
    self.textarea,
    "height",
    "\{clamped_height.to_string()}px",
  )
}

// --- helpers / FFI ---------------------------------------------------------------

///|
fn is_blank(text : String) -> Bool {
  for ch in text {
    if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      return false
    }
  }
  true
}

///|
/// FFI gap-fills, following the comment widget's extern pattern.
extern "js" fn input_textarea_value(element : @rdom.Element) -> String = "(el) => el.value ?? ''"

///|
extern "js" fn input_set_textarea_value(
  element : @rdom.Element,
  value : String,
) -> Unit = "(el, v) => { el.value = v }"

///|
/// Resets the textarea height to `auto` and reports the content height —
/// upstream's two-step `height = 'auto'; height = scrollHeight`.
extern "js" fn input_textarea_grown_height(element : @rdom.Element) -> Double =
  #| (el) => { el.style.height = 'auto'; return el.scrollHeight ?? 0 }

///|
/// Whether the event's target is (inside) the given element.
extern "js" fn input_event_targets(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (ev, el) => el === ev.target || (el.contains?.(ev.target) ?? false)
