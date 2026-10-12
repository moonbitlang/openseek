///|
/// The same floating composer used by code and Markdown. The host supplies
/// a live selection anchor, source identity, and conversation routing.
struct FeedbackInput {
  widget : @feedback.AgentFeedbackInputWidget
  container : @rdom.Element
  mut anchor : (() -> @rdom.DOMRect?)?
  mut prefer_below : Bool
  subscriptions : Array[@base_common.Disposable]
}

///|
pub fn FeedbackInput::FeedbackInput(
  container : @rdom.Element,
  viewport~ : @rdom.Element,
  layout_source~ : @rdom.Element,
  localization~ : @localization.Localization,
  on_submit~ : (String, Bool) -> Unit,
  on_change~ : (String) -> Unit,
  on_cancel~ : () -> Unit,
) -> FeedbackInput {
  let mut slot : FeedbackInput? = None
  let submit = apply => {
    if slot is Some(input) {
      on_submit(input.widget.value(), apply)
    }
  }
  let layout = () => if slot is Some(input) { input.layout() }
  let widget = @feedback.AgentFeedbackInputWidget(
    localization~,
    {
      on_add: () => submit(false),
      on_add_and_submit: () => submit(true),
      on_cancel,
      on_layout: layout,
      on_blur_empty: on_cancel,
      content_width: () => @base_browser.element_client_width(container),
    },
    on_change~,
  )
  let input : FeedbackInput = {
    widget,
    container,
    anchor: None,
    prefer_below: true,
    subscriptions: [],
  }
  slot = Some(input)
  container.append_child(widget.get_dom_node().as_node())
  input.subscriptions.push(localization.bind(_ => widget.refresh_labels()))
  if @base_browser.observe_element_resize(container, layout)
    is Some(subscription) {
    input.subscriptions.push(subscription)
  }
  if @base_browser.observe_element_resize(layout_source, layout)
    is Some(subscription) {
    input.subscriptions.push(subscription)
  }
  // Document renderers can replace text nodes without resizing their viewport.
  // Observe only the source subtree, never the composer we lay out here.
  let changed : (FixedArray[@js.Value], @js.Value) -> Unit = (_, _) => layout()
  let observer : @js.Value = @js.globalThis.new_with_string(
    "MutationObserver",
    [changed],
  )
  let options = @js.Object::new()
  options.set("childList", true)
  options.set("subtree", true)
  options.set("attributes", true)
  options.set("characterData", true)
  let _ : @js.Value = observer.apply_with_string("observe", [
    @js.Value::cast_from(layout_source),
    options.to_value(),
  ])
  input.subscriptions.push(
    @base_common.Disposable::from(() => {
      let _ : @js.Value = observer.apply_with_string(
        "disconnect",
        ([] : FixedArray[@js.Value]),
      )
    }),
  )
  let scroll : @rdom.Listener = _ => layout()
  viewport.add_event_listener_with_options("scroll", scroll, capture=true)
  input.subscriptions.push(
    @base_common.Disposable::from(() => {
      viewport.remove_event_listener_with_options(
        "scroll",
        scroll,
        capture=true,
      )
    }),
  )
  let keydown : @rdom.Listener = event => {
    guard input.anchor is Some(_) &&
      event.to_keyboard_event() is Some(key) &&
      !key.is_composing() else {
      return
    }
    if key.key() == "Escape" {
      event.prevent_default()
      event.stop_propagation()
      on_cancel()
    } else if key.key() == "i" &&
      (key.ctrl_key() || key.meta_key()) &&
      !key.alt_key() &&
      !key.shift_key() {
      event.prevent_default()
      event.stop_propagation()
      widget.focus_input()
    }
  }
  viewport.add_event_listener("keydown", keydown)
  input.subscriptions.push(
    @base_common.Disposable::from(() => {
      viewport.remove_event_listener("keydown", keydown)
    }),
  )
  input
}

///|
/// Preserve Batch while attaching a fresh, live source anchor.
pub fn FeedbackInput::show(
  self : FeedbackInput,
  anchor : () -> @rdom.DOMRect?,
  prefer_below~ : Bool,
) -> Unit {
  self.anchor = Some(anchor)
  self.prefer_below = prefer_below
  self.widget.clear_input()
  self.widget.show()
  self.layout()
}

///|
fn FeedbackInput::layout(self : FeedbackInput) -> Unit {
  guard self.anchor is Some(measure) else { return }
  guard measure() is Some(anchor) else {
    self.widget.hide()
    return
  }
  self.widget.resize()
  let root = self.container.get_bounding_client_rect()
  let width = self.widget.measured_width()
  let height = self.widget.measured_height()
  if anchor.get_bottom() < root.get_top() ||
    anchor.get_top() > root.get_bottom() {
    self.widget.hide()
    return
  }
  self.widget.show()
  let left = (anchor.get_left() - root.get_left())
    .max(0.0)
    .min((root.get_width() - width).max(0.0))
  let below = anchor.get_bottom() - root.get_top()
  let above = anchor.get_top() - root.get_top() - height
  let top = if self.prefer_below {
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
  self.widget.set_position(top.min(root.get_height() - height).max(0.0), left)
}

///|
pub fn FeedbackInput::hide(self : FeedbackInput) -> Unit {
  self.anchor = None
  self.widget.hide()
  self.widget.clear_input()
}

///|
pub fn FeedbackInput::dispose(self : FeedbackInput) -> Unit {
  self.anchor = None
  for subscription in self.subscriptions {
    subscription.dispose()
  }
  self.subscriptions.clear()
  @base_browser.remove_element(self.widget.get_dom_node())
}
