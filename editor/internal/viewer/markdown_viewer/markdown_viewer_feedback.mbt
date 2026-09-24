///|
/// One model attachment's selection and feedback composer. IDs are resolved by
/// the document before opening the composer; submissions retain source ranges.
priv struct MarkdownViewerWidgetFeedbackBridge {
  viewer : MarkdownViewerWidget
  view : @markdown_document.MarkdownDocumentView
  model : @model.TextModel
  attach_generation : Int
  service : @agent_feedback_api.AgentFeedbackHandle
  input : @agent_feedback_browser.AgentFeedbackInputWidget
  listeners : Array[@base_common.Disposable]
  mut target : @markdown_document.MarkdownSourceSelection?
  mut dismissed_target : @markdown_document.MarkdownSourceSelection?
  mut visible : Bool
  mut mouse_down : Bool
  mut disposed : Bool
}

///|
fn MarkdownViewerWidgetFeedbackBridge::MarkdownViewerWidgetFeedbackBridge(
  viewer : MarkdownViewerWidget,
  view : @markdown_document.MarkdownDocumentView,
  model : @model.TextModel,
  attach_generation : Int,
  service : @agent_feedback_api.AgentFeedbackHandle,
) -> MarkdownViewerWidgetFeedbackBridge {
  let mut slot : MarkdownViewerWidgetFeedbackBridge? = None
  let input = @agent_feedback_browser.AgentFeedbackInputWidget(
    localization=viewer.services.localization,
    {
      on_add: () => if slot is Some(bridge) { bridge.submit(false) },
      on_add_and_submit: () => if slot is Some(bridge) { bridge.submit(true) },
      on_cancel: () => {
        if slot is Some(bridge) {
          bridge.hide()
          viewer.focus()
        }
      },
      on_layout: () => if slot is Some(bridge) { bridge.layout() },
      on_blur_empty: () => if slot is Some(bridge) { bridge.auto_hide() },
      content_width: () => view.root().get_bounding_client_rect().get_width(),
    },
  )
  let bridge : MarkdownViewerWidgetFeedbackBridge = {
    viewer,
    view,
    model,
    attach_generation,
    service,
    input,
    listeners: [],
    target: None,
    dismissed_target: None,
    visible: false,
    mouse_down: false,
    disposed: false,
  }
  slot = Some(bridge)
  view.overlay_mount().append_child(input.get_dom_node().as_node())
  bridge
}

///|
fn MarkdownViewerWidgetFeedbackBridge::is_current(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Bool {
  !self.disposed &&
  !self.model.is_disposed() &&
  self.viewer.is_current_attachment(self.model, self.attach_generation) &&
  self.view.source_model_version() == self.model.get_version_id() &&
  self.service.is_feedback_enabled(self.model.uri)
}

///|
fn MarkdownViewerWidgetFeedbackBridge::target_is_current(
  self : MarkdownViewerWidgetFeedbackBridge,
  target : @markdown_document.MarkdownSourceSelection,
) -> Bool {
  self.is_current() &&
  target.source_model_version == self.model.get_version_id() &&
  target.projection_generation == self.view.projection_generation()
}

///|
fn MarkdownViewerWidgetFeedbackBridge::listen(
  self : MarkdownViewerWidgetFeedbackBridge,
  target : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
fn MarkdownViewerWidgetFeedbackBridge::activate(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  let selection_changed : @rdom.Listener = _ => self.selection_changed()
  @rdom.document().add_event_listener("selectionchange", selection_changed)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      @rdom.document().remove_event_listener(
        "selectionchange", selection_changed,
      )
    }),
  )
  self.listen(self.view.root(), "mousedown", event => {
    if @base_browser.event_target_has_matching_ancestor(
        event,
        self.view.root(),
        "button, input, textarea, select",
      ) {
      self.auto_hide()
      return
    }
    self.mouse_down = true
    self.auto_hide()
    // A deliberate new selection may target the same text as the last one.
    self.dismissed_target = None
  })
  // The pointer can finish a drag outside the document viewport.
  let mouse_up : @rdom.Listener = _ => {
    if self.mouse_down {
      self.mouse_down = false
      self.selection_changed()
    }
  }
  @rdom.document().add_event_listener("mouseup", mouse_up)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      @rdom.document().remove_event_listener("mouseup", mouse_up)
    }),
  )
  self.listen(self.view.viewport(), "scroll", _ => {
    if self.visible {
      self.layout()
    }
  })
  self.listen(self.view.root(), "keydown", event => {
    guard self.visible && event.to_keyboard_event() is Some(key) else { return }
    if key.key() == "Escape" {
      event.prevent_default()
      self.hide()
    } else if key.key() == "i" &&
      (key.ctrl_key() || key.meta_key()) &&
      !key.shift_key() &&
      !key.alt_key() {
      event.prevent_default()
      event.stop_propagation()
      self.input.focus_input()
    }
  })
  self.listeners.push(
    self.service.on_did_change_feedback(_ => {
      if !self.is_current() {
        self.hide()
      }
    }),
  )
}

///|
fn MarkdownViewerWidgetFeedbackBridge::selection_changed(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  guard self.is_current() else {
    self.hide()
    return
  }
  if self.mouse_down ||
    !@base_browser.element_contains_active_element(self.view.root()) ||
    @base_browser.element_contains_active_element(self.input.get_dom_node()) ||
    self.view
    .root()
    .query_selector("button:focus, input:focus, textarea:focus, select:focus")
    is Some(_) {
    return
  }
  // Match the code editor: only a non-empty draft pins the source target.
  if self.visible && self.input.has_text() {
    return
  }
  guard self.view.source_selection() is Some(target) else {
    self.auto_hide()
    return
  }
  if self.dismissed_target is Some(dismissed) &&
    target.same_dom_range(dismissed) {
    return
  }
  self.dismissed_target = None
  self.target = Some(target)
  self.visible = true
  self.input.set_placeholder(
    self.viewer.services.localization.text(AddFeedback),
  )
  self.input.clear_input()
  self.input.show()
  self.layout()
  // Keep document focus so copy and keyboard selection continue to work.
  // The shared input is focused by a click or Ctrl/Cmd+I, as in code views.
}

///|
fn MarkdownViewerWidgetFeedbackBridge::layout(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  guard self.visible else { return }
  guard self.target is Some(target) && self.target_is_current(target) else {
    self.hide()
    return
  }
  let root = self.view.root().get_bounding_client_rect()
  let width = self.input.measured_width()
  let height = self.input.measured_height()
  let anchor = target.anchor_client_rect()
  let left = (anchor.get_left() - root.get_left())
    .max(0.0)
    .min((root.get_width() - width).max(0.0))
  let below = anchor.get_bottom() - root.get_top()
  let above = anchor.get_top() - root.get_top() - height
  let top = if target.prefer_below {
    if below + height > root.get_height() {
      above
    } else {
      below
    }
  } else if above < 0.0 {
    below
  } else {
    above
  }
  self.input.set_position(top.min(root.get_height() - height).max(0.0), left)
}

///|
fn MarkdownViewerWidgetFeedbackBridge::submit(
  self : MarkdownViewerWidgetFeedbackBridge,
  apply : Bool,
) -> Unit {
  guard self.visible &&
    self.target is Some(target) &&
    self.target_is_current(target) else {
    self.hide()
    return
  }
  let text = self.input.value().trim().to_owned()
  guard !text.is_empty() else { return }
  let start = self.model.get_position_at(target.source_range.start)
  let end = self.model.get_position_at(target.source_range.end_exclusive)
  self.service.add_feedback(
    self.model.uri,
    Range(start.line_number, start.column, end.line_number, end.column),
    text,
  )
  |> ignore
  self.hide()
  self.viewer.focus()
  if apply {
    self.service.mark_feedback_submitted(self.model.uri)
  }
}

///|
fn MarkdownViewerWidgetFeedbackBridge::hide(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  guard self.visible else { return }
  let dismissed = match self.view.source_selection() {
    Some(current) => Some(current)
    None => self.target
  }
  if dismissed is Some(target) {
    // Native Selection may survive textarea focus and editor refocus. Do not
    // reopen it on the resulting selectionchange event. A typed draft may
    // still refer to an earlier range than the current native selection.
    self.dismissed_target = Some(target)
  }
  self.target = None
  self.visible = false
  self.input.hide()
  self.input.clear_input()
}

///|
fn MarkdownViewerWidgetFeedbackBridge::auto_hide(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  if !self.input.has_text() {
    self.hide()
  }
}

///|
fn MarkdownViewerWidgetFeedbackBridge::dispose(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.hide()
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  @base_browser.remove_element(self.input.get_dom_node())
}
