// The compact inline feedback composer. Batch keeps a note in the host's
// accepted-feedback collection; otherwise submission applies all feedback.
// The native checkbox retains this choice while the widget lives. Enter
// follows that choice, Alt+Enter always applies, Shift+Enter inserts a line,
// and Escape cancels. The glue positions the overlay beside its pinned range.

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
let input_min_height_px : Double = 30.0

///|
let input_max_height_px : Double = 140.0

///|
/// The glue-facing seam: submit/cancel routing plus the geometry reads the
/// widget needs while sizing (the upstream widget reached back into
/// `ICodeEditor.getLayoutInfo` for these).
pub(all) struct AgentFeedbackInputWidgetHost {
  /// Submit with Batch checked — `onDidTriggerAdd`.
  on_add : () -> Unit
  /// Submit without Batch, or Alt+Enter — `onDidTriggerAddAndSubmit`.
  on_add_and_submit : () -> Unit
  /// Escape inside the composer — the contribution hides and refocuses.
  on_cancel : () -> Unit
  /// The textarea grew/shrank; the glue repositions the widget
  /// (`this._updatePosition()` on `input`).
  on_layout : () -> Unit
  /// Focus left the composer with no draft text; the glue auto-hides.
  on_blur_empty : () -> Unit
  /// `_computeMaxWidth`'s editor content width (layout width − content left).
  content_width : () -> Double
}

///|
struct AgentFeedbackInputWidget {
  localization : @localization.Localization
  host : AgentFeedbackInputWidgetHost
  root : @rdom.Element
  textarea : @rdom.Element
  batch_label : @rdom.Element
  batch_text : @rdom.Element
  batch : @rdom.Element
  submit : @rdom.Element
}

///|
pub fn AgentFeedbackInputWidget::AgentFeedbackInputWidget(
  localization? : @localization.Localization = Localization(),
  host : AgentFeedbackInputWidgetHost,
) -> AgentFeedbackInputWidget {
  let document = @rdom.document()
  let root = document.create_element("div")
  root.set_attribute("class", "agent-feedback-input-widget")
  root.set_attribute("style", "display:none")
  root.set_attribute("role", "dialog")
  root.set_attribute("aria-label", localization.text(AddFeedback))
  let textarea = document.create_element("textarea")
  textarea.set_attribute("rows", "1")
  textarea.set_attribute("placeholder", localization.text(AddFeedback))
  textarea.set_attribute("aria-label", localization.text(FeedbackLabel))
  textarea.set_attribute("data-agent-feedback-input", "true")
  root.append_child(textarea.as_node())
  let actions = document.create_element("div")
  actions.set_attribute("class", "agent-feedback-input-actions")
  let batch_label = document.create_element("label")
  batch_label.set_attribute("class", "agent-feedback-input-batch")
  let batch = document.create_element("input")
  batch.set_attribute("type", "checkbox")
  let batch_text = document.create_element("span")
  batch_label.append_child(batch.as_node())
  batch_label.append_child(batch_text.as_node())
  let submit = document.create_element("button")
  submit.set_attribute("type", "button")
  submit.set_attribute("class", "agent-feedback-input-action")
  submit.set_inner_html(
    "<span class=\"agent-feedback-input-icon\" aria-hidden=\"true\"></span>",
  )
  actions.append_child(batch_label.as_node())
  actions.append_child(submit.as_node())
  root.append_child(actions.as_node())
  let widget : AgentFeedbackInputWidget = {
    localization,
    host,
    root,
    textarea,
    batch_label,
    batch_text,
    batch,
    submit,
  }
  widget.refresh_labels()
  widget.update_actions_enabled()
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
      !input_event_targets(event, self.batch_label) &&
      !input_event_targets(event, self.submit) {
      event.prevent_default()
      @base_browser.focus_prevent_scroll(self.textarea)
    }
  })
  self.batch.add_event_listener("change", _ => {
    self.refresh_labels()
    self.auto_size()
    (self.host.on_layout)()
    @base_browser.focus_prevent_scroll(self.textarea)
  })
  self.submit.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    self.submit_feedback(force_apply=false)
  })
  self.root.add_event_listener("keydown", event => {
    if event.to_keyboard_event() is Some(keyboard) &&
      keyboard.key() == "Escape" &&
      !keyboard.is_composing() {
      event.prevent_default()
      (self.host.on_cancel)()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) => self.handle_keydown(event, keyboard)
      None => ()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("input", _ => {
    self.auto_size()
    self.update_actions_enabled()
    (self.host.on_layout)()
  })
  self.root.add_event_listener("focusout", event => {
    // Tabbing or clicking into Batch is still inside the composer. In
    // particular, an empty draft must survive toggling the checkbox.
    let next = event
      .to_focus_event()
      .bind(focus => focus.related_target())
      .bind(target => target.to_element())
    if next is Some(element) &&
      @base_browser.element_contains(self.root, element) {
      return
    }
    if !self.has_text() {
      (self.host.on_blur_empty)()
    }
  })
}

///|
fn AgentFeedbackInputWidget::submit_feedback(
  self : AgentFeedbackInputWidget,
  force_apply~ : Bool,
) -> Unit {
  guard self.has_text() else { return }
  if force_apply || !input_checkbox_checked(self.batch) {
    (self.host.on_add_and_submit)()
  } else {
    (self.host.on_add)()
  }
}

///|
fn AgentFeedbackInputWidget::handle_keydown(
  self : AgentFeedbackInputWidget,
  event : @rdom.Event,
  keyboard : @rdom.KeyboardEvent,
) -> Unit {
  guard !keyboard.is_composing() else { return }
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
      self.submit_feedback(force_apply=keyboard.alt_key())
    }
    _ => ()
  }
}

// --- glue-facing surface ---------------------------------------------------------

///|
pub fn AgentFeedbackInputWidget::show(self : AgentFeedbackInputWidget) -> Unit {
  self.refresh_labels()
  @base_browser.set_style_property(self.root, "display", "")
}

///|
pub fn AgentFeedbackInputWidget::refresh_labels(
  self : AgentFeedbackInputWidget,
) -> Unit {
  self.textarea.set_attribute(
    "placeholder",
    self.localization.text(AddFeedback),
  )
  self.textarea.set_attribute(
    "aria-label",
    self.localization.text(FeedbackLabel),
  )
  self.root.set_attribute("aria-label", self.localization.text(AddFeedback))
  self.batch_text.set_inner_html(self.localization.text(BatchLabel))
  self.batch_label.set_attribute(
    "title",
    self.localization.text(BatchFeedbackHint),
  )
  let batched = input_checkbox_checked(self.batch)
  self.submit.set_attribute(
    "data-agent-feedback-action",
    if batched {
      "add"
    } else {
      "apply"
    },
  )
  self.submit.set_attribute(
    "title",
    self.localization.text(
      if batched {
        AddFeedbackBatch
      } else {
        ApplyFeedbackShortcut
      },
    ),
  )
  self.submit.set_attribute(
    "aria-label",
    self.localization.text(if batched { AddFeedback } else { ApplyFeedback }),
  )
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
  self.update_actions_enabled()
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
    52.0
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
fn AgentFeedbackInputWidget::update_actions_enabled(
  self : AgentFeedbackInputWidget,
) -> Unit {
  if self.has_text() {
    self.submit.remove_attribute("disabled")
  } else {
    self.submit.set_attribute("disabled", "true")
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

///|
extern "js" fn input_checkbox_checked(element : @rdom.Element) -> Bool = "(el) => el.checked"
