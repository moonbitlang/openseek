///|
/// The same floating composer used by code and Markdown. The host supplies
/// a live selection anchor, source identity, and conversation routing.
struct FeedbackComposerWidget {
  widget : AgentFeedbackInputWidget
  container : @rdom.Element
  mut anchor : (() -> @rdom.DOMRect?)?
  selection_layer : @rdom.Element
  mut selection_rects : () -> Array[@rdom.DOMRect]
  mut prefer_below : Bool
  subscriptions : Array[@base_common.Disposable]
}

///|
pub fn FeedbackComposerWidget::FeedbackComposerWidget(
  container : @rdom.Element,
  viewport~ : @rdom.Element,
  layout_source~ : @rdom.Element,
  localization~ : @localization.Localization,
  on_submit~ : (String, Bool) -> Unit,
  on_change~ : (String) -> Unit,
  on_cancel~ : () -> Unit,
) -> FeedbackComposerWidget {
  let mut slot : FeedbackComposerWidget? = None
  let submit = apply => {
    if slot is Some(input) {
      on_submit(input.widget.value(), apply)
    }
  }
  let layout = () => if slot is Some(input) { input.layout() }
  let widget = AgentFeedbackInputWidget(
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
  let selection_layer = @rdom.document().create_element("div")
  selection_layer.set_attribute("class", "feedback-source-selection-layer")
  selection_layer.set_attribute("aria-hidden", "true")
  container.append_child(selection_layer.as_node())
  let input : FeedbackComposerWidget = {
    widget,
    container,
    anchor: None,
    selection_layer,
    selection_rects: () => [],
    prefer_below: true,
    subscriptions: [],
  }
  slot = Some(input)
  container.append_child(widget.get_dom_node().as_node())
  // Selection opens the composer without moving focus. An outside click
  // must therefore dismiss an empty draft even if no focusout can fire.
  // Match the editor's auto-hide policy: typed drafts stay pinned.
  let pointer_down : @rdom.Listener = event => {
    guard input.anchor is Some(_) && !widget.has_text() else { return }
    if event.target().to_element() is Some(target) &&
      @base_browser.element_contains(widget.get_dom_node(), target) {
      return
    }
    if event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 {
      on_cancel()
    }
  }
  @rdom.document().add_event_listener_with_options(
    "pointerdown",
    pointer_down,
    capture=true,
  )
  input.subscriptions.push(
    @base_common.Disposable::from(() => {
      @rdom.document().remove_event_listener_with_options(
        "pointerdown",
        pointer_down,
        capture=true,
      )
    }),
  )
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
pub fn FeedbackComposerWidget::show(
  self : FeedbackComposerWidget,
  anchor : () -> @rdom.DOMRect?,
  prefer_below~ : Bool,
  selection_rects~ : () -> Array[@rdom.DOMRect],
) -> Unit {
  self.selection_rects = selection_rects
  self.anchor = Some(anchor)
  self.prefer_below = prefer_below
  self.widget.clear_input()
  self.widget.show()
  self.layout()
}

///|
fn FeedbackComposerWidget::layout(self : FeedbackComposerWidget) -> Unit {
  guard self.anchor is Some(measure) else { return }
  self.paint_selection()
  guard measure() is Some(anchor) else {
    self.widget.hide()
    return
  }
  let root = self.container.get_bounding_client_rect()
  if anchor.get_bottom() < root.get_top() ||
    anchor.get_top() > root.get_bottom() ||
    anchor.get_right() < root.get_left() ||
    anchor.get_left() > root.get_right() {
    self.widget.hide()
    return
  }
  self.widget.show()
  // Hidden textareas have no scrollHeight. Restore visibility before sizing
  // so both the draft height and the popup position use rendered geometry.
  self.widget.resize()
  let width = self.widget.measured_width()
  let height = self.widget.measured_height()
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
pub fn FeedbackComposerWidget::hide(self : FeedbackComposerWidget) -> Unit {
  self.anchor = None
  self.selection_rects = () => []
  self.selection_layer.set_inner_html("")
  self.widget.hide()
  self.widget.clear_input()
}

///|
pub fn FeedbackComposerWidget::dispose(self : FeedbackComposerWidget) -> Unit {
  self.anchor = None
  self.selection_rects = () => []
  self.selection_layer.set_inner_html("")
  for subscription in self.subscriptions {
    subscription.dispose()
  }
  self.subscriptions.clear()
  @base_browser.remove_element(self.selection_layer)
  @base_browser.remove_element(self.widget.get_dom_node())
}

///|
/// Retain source feedback even when focusing the textarea replaces the native
/// selection. Clip each fragment to this viewport, independently of the popup.
fn FeedbackComposerWidget::paint_selection(
  self : FeedbackComposerWidget,
) -> Unit {
  self.selection_layer.set_inner_html("")
  let root = self.container.get_bounding_client_rect()
  for rect in (self.selection_rects)() {
    let left = rect.get_left().max(root.get_left())
    let top = rect.get_top().max(root.get_top())
    let right = rect.get_right().min(root.get_right())
    let bottom = rect.get_bottom().min(root.get_bottom())
    guard right > left && bottom > top else { continue }
    let fragment = @rdom.document().create_element("div")
    fragment.set_attribute("class", "feedback-source-selection")
    @base_browser.set_style_property(
      fragment,
      "left",
      "\{left - root.get_left()}px",
    )
    @base_browser.set_style_property(
      fragment,
      "top",
      "\{top - root.get_top()}px",
    )
    @base_browser.set_style_property(fragment, "width", "\{right - left}px")
    @base_browser.set_style_property(fragment, "height", "\{bottom - top}px")
    self.selection_layer.append_child(fragment.as_node())
  }
}
