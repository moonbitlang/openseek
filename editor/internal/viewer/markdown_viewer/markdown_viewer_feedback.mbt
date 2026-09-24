///|
/// One model attachment's selection and feedback composer. IDs are resolved by
/// the document before opening the composer; submissions retain source ranges.
priv struct MarkdownViewerWidgetFeedbackBridge {
  viewer : MarkdownViewerWidget
  view : @markdown_document.MarkdownDocumentView
  model : @model.TextModel
  attach_generation : Int
  service : @agent_feedback_api.AgentFeedbackHandle
  button : @rdom.Element
  input : @agent_feedback_browser.AgentFeedbackInputWidget
  listeners : Array[@base_common.Disposable]
  mut target : @markdown_document.MarkdownSourceSelection?
  mut editing : Bool
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
  let button = @rdom.document().create_element("button")
  button.set_attribute("type", "button")
  button.set_attribute("class", "moonbit-viewer-markdown-feedback-add")
  button.set_attribute("data-markdown-feedback-add", "true")
  button.set_attribute("style", "display:none")
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
      on_blur_empty: () => if slot is Some(bridge) { bridge.hide() },
      content_width: () => view.root().get_bounding_client_rect().get_width(),
    },
  )
  let bridge : MarkdownViewerWidgetFeedbackBridge = {
    viewer,
    view,
    model,
    attach_generation,
    service,
    button,
    input,
    listeners: [],
    target: None,
    editing: false,
    disposed: false,
  }
  slot = Some(bridge)
  view.overlay_mount().append_child(button.as_node())
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
  self.listen(self.view.root(), "mouseup", _ => self.selection_changed())
  self.listen(self.view.viewport(), "scroll", _ => {
    if self.editing {
      self.layout()
    } else {
      self.selection_changed()
    }
  })
  self.listen(self.button, "mousedown", event => event.prevent_default())
  self.listen(self.button, "click", event => {
    event.prevent_default()
    event.stop_propagation()
    guard self.target is Some(target) && self.target_is_current(target) else {
      self.hide()
      return
    }
    self.editing = true
    self.button.set_attribute("style", "display:none")
    self.input.show()
    self.layout()
    self.input.focus_input()
  })
  self.listen(self.view.root(), "keydown", event => {
    if event.to_keyboard_event() is Some(key) && key.key() == "Escape" {
      self.hide()
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
  if self.editing {
    return
  }
  self.target = self.view.source_selection()
  if self.target is Some(_) {
    self.button.set_inner_html(
      self.viewer.services.localization.text(AddFeedback),
    )
    self.button.set_attribute("style", "display:block")
    self.layout()
  } else {
    self.button.set_attribute("style", "display:none")
  }
}

///|
fn MarkdownViewerWidgetFeedbackBridge::layout(
  self : MarkdownViewerWidgetFeedbackBridge,
) -> Unit {
  guard self.target is Some(target) && self.target_is_current(target) else {
    self.hide()
    return
  }
  let root = self.view.root().get_bounding_client_rect()
  let box = if self.editing { self.input.get_dom_node() } else { self.button }
  let size = box.get_bounding_client_rect()
  let selected = target.client_rect()
  let left = (selected.get_right() - root.get_left() - size.get_width())
    .max(8.0)
    .min((root.get_width() - size.get_width() - 8.0).max(8.0))
  let below = selected.get_bottom() - root.get_top() + 6.0
  let top = if below + size.get_height() <= root.get_height() {
    below
  } else {
    (selected.get_top() - root.get_top() - size.get_height() - 6.0).max(8.0)
  }
  if self.editing {
    self.input.set_position(top, left)
  } else {
    self.button.set_attribute(
      "style",
      "display:block;top:\{top}px;left:\{left}px",
    )
  }
}

///|
fn MarkdownViewerWidgetFeedbackBridge::submit(
  self : MarkdownViewerWidgetFeedbackBridge,
  apply : Bool,
) -> Unit {
  guard self.editing &&
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
  self.target = None
  self.editing = false
  self.button.set_attribute("style", "display:none")
  self.input.hide()
  self.input.clear_input()
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
  @base_browser.remove_element(self.button)
  @base_browser.remove_element(self.input.get_dom_node())
}
