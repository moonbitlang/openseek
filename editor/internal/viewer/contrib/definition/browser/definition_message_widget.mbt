///|
/// Monaco's `MessageWidget` (`messageController.ts`), reduced to the
/// definition action's plain-text message. The widget retains a model-space
/// anchor and exposes the standard content-widget contract; the root Viewer
/// owns mounting, layout, and dismissal policy.
struct DefinitionMessageWidget {
  root : @rdom.Element
  message : @rdom.Element
  mut position : @base_common.Position?
  mut disposed : Bool
}

///|
/// Constructs Monaco's detached, hidden overlay-message DOM.
pub fn DefinitionMessageWidget::DefinitionMessageWidget() -> DefinitionMessageWidget {
  let document = @rdom.document()
  let root = @rdom.document().create_element("div")
  root.set_attribute(
    "class", "monaco-editor-overlaymessage moonbit-viewer-definition-message",
  )
  root.set_attribute("role", "status")
  root.set_attribute("aria-live", "polite")
  root.set_attribute("aria-atomic", "true")
  root.set_attribute("hidden", "")
  root.set_attribute("aria-hidden", "true")
  let anchor_top = document.create_element("div")
  anchor_top.set_attribute("class", "anchor top")
  root.append_child(anchor_top.as_node())
  let message = document.create_element("div")
  message.set_attribute("class", "message")
  root.append_child(message.as_node())
  let anchor_below = document.create_element("div")
  anchor_below.set_attribute("class", "anchor below")
  root.append_child(anchor_below.as_node())
  { root, message, position: None, disposed: false, }
}

///|
/// Detached root node mounted by the root Viewer.
pub fn DefinitionMessageWidget::get_dom_node(
  self : DefinitionMessageWidget,
) -> @rdom.Element {
  self.root
}

///|
/// Replaces the message text without changing visibility.
pub fn DefinitionMessageWidget::set_message(
  self : DefinitionMessageWidget,
  message : String,
) -> Unit {
  if self.disposed {
    return
  }
  self.message.set_inner_html("")
  self.message.append_child(
    @rdom.document().create_text_node(message).as_node(),
  )
}

///|
/// Shows the current message at the exact request position.
pub fn DefinitionMessageWidget::show_at(
  self : DefinitionMessageWidget,
  position : @base_common.Position,
) -> Unit {
  if self.disposed {
    return
  }
  self.position = Some(position)
  self.root.set_attribute(
    "class", "monaco-editor-overlaymessage moonbit-viewer-definition-message fadeIn",
  )
  self.root.remove_attribute("hidden")
  self.root.set_attribute("aria-hidden", "false")
}

///|
/// Hides the status without discarding its text.
pub fn DefinitionMessageWidget::hide(self : DefinitionMessageWidget) -> Unit {
  if self.disposed {
    return
  }
  self.position = None
  self.root.set_attribute("hidden", "")
  self.root.set_attribute("aria-hidden", "true")
}

///|
fn DefinitionMessageWidget::content_widget_position(
  self : DefinitionMessageWidget,
) -> @view.ContentWidgetPosition? {
  match self.position {
    Some(position) =>
      Some({
        position: Some(position),
        secondary_position: None,
        preference: Some([Above, Below]),
        position_affinity: Some(Right),
      })
    None => None
  }
}

///|
fn DefinitionMessageWidget::after_render(
  self : DefinitionMessageWidget,
  preference : @view.ContentWidgetPositionPreference?,
) -> Unit {
  guard !self.disposed else { return }
  let below = if preference is Some(Below) { " below" } else { "" }
  self.root.set_attribute(
    "class",
    "monaco-editor-overlaymessage moonbit-viewer-definition-message fadeIn\{below}",
  )
}

///|
/// Adapts the message to Monaco's overflowing content-widget contract.
pub fn DefinitionMessageWidget::content_widget_handle(
  self : DefinitionMessageWidget,
) -> @view.ContentWidgetHandle {
  ContentWidgetHandle(
    () => "editor.contrib.definition.message",
    () => self.root,
    () => self.content_widget_position(),
    allow_editor_overflow=true,
    after_render=preference => self.after_render(preference),
  )
}

///|
/// Hides and clears the detached status node exactly once.
pub fn DefinitionMessageWidget::dispose(self : DefinitionMessageWidget) -> Unit {
  if self.disposed {
    return
  }
  self.position = None
  self.root.set_attribute("hidden", "")
  self.root.set_attribute("aria-hidden", "true")
  self.message.set_inner_html("")
  self.disposed = true
}
