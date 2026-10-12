///|
/// The same composer used by code and Markdown, mounted in a host-owned slot.
/// The host owns source anchors and routes accepted text to its conversation.
struct FeedbackInput {
  widget : @feedback.AgentFeedbackInputWidget
  localization_subscription : @base_common.Disposable
}

///|
pub fn FeedbackInput::FeedbackInput(
  container : @rdom.Element,
  localization~ : @localization.Localization,
  on_submit~ : (String, Bool) -> Unit,
  on_change~ : (String) -> Unit,
  on_cancel~ : () -> Unit,
) -> FeedbackInput {
  let mut slot : @feedback.AgentFeedbackInputWidget? = None
  let submit = apply => {
    if slot is Some(widget) {
      on_submit(widget.value(), apply)
    }
  }
  let widget = @feedback.AgentFeedbackInputWidget(
    localization~,
    {
      on_add: () => submit(false),
      on_add_and_submit: () => submit(true),
      on_cancel,
      on_layout: () => (),
      on_blur_empty: () => (),
      content_width: () => @base_browser.element_client_width(container),
    },
    on_change~,
  )
  slot = Some(widget)
  let root = widget.get_dom_node()
  @base_browser.set_style_property(root, "position", "relative")
  container.append_child(root.as_node())
  {
    widget,
    localization_subscription: localization.bind(_ => widget.refresh_labels()),
  }
}

///|
/// Start a new selection while retaining the user's Batch preference.
pub fn FeedbackInput::show(self : FeedbackInput) -> Unit {
  self.widget.clear_input()
  self.widget.show()
}

///|
pub fn FeedbackInput::hide(self : FeedbackInput) -> Unit {
  self.widget.hide()
  self.widget.clear_input()
}

///|
pub fn FeedbackInput::dispose(self : FeedbackInput) -> Unit {
  self.localization_subscription.dispose()
  @base_browser.remove_element(self.widget.get_dom_node())
}
