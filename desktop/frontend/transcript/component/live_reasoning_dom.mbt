///|
/// Imperative DOM state for the childless live-reasoning host. This object is
/// captured by the component's private update closure; it is never stored in
/// a Rabbita model or exposed to the root view.
priv struct LivePreview {
  mut target : String?
  mut step_label : String?
  mut host : @dom.Element?
  mut reasoning : @dom.Element?
  // The one text node fragments are appended to. The browser appends in
  // place, so no copy of the accumulated text lives on this side.
  mut text : @dom.Element?
  pending : Array[String]
  mut frame : Double?
  mut resize : @dom.ResizeObserver?
  // Whether the reader follows the tail. The transcript component mirrors
  // its Model here from its subscription, after every message.
  mut pinned : Bool
}

///|
fn LivePreview::LivePreview() -> LivePreview {
  {
    target: None,
    step_label: None,
    host: None,
    reasoning: None,
    text: None,
    pending: [],
    frame: None,
    resize: None,
    pinned: true,
  }
}

///|
/// The stable container Rabbita renders for the preview (see
/// `section_children`). Absent while no transcript is on screen.
fn live_host() -> @dom.Element? {
  @dom.document().get_element_by_id("live-reasoning-host").to_option()
}

///|
/// Cancel a queued frame before changing ownership. Clearing the fragments at
/// the same time prevents a callback from one conversation from appending to
/// a replacement conversation's card.
fn LivePreview::cancel_pending(self : LivePreview) -> Unit {
  if self.frame is Some(frame) {
    @dom.window().cancel_animation_frame(frame)
    self.frame = None
  }
  self.pending.clear()
}

///|
/// Remove only the descendants owned by this widget. The host itself belongs
/// to Rabbita and remains a stable childless virtual-DOM node.
fn LivePreview::clear_host(self : LivePreview, host : @dom.Element?) -> Unit {
  if self.resize is Some(resize) {
    resize.disconnect()
  }
  if host is Some(host) {
    while host.get_child_count() > 0 {
      host.remove_child(host.get_child(0))
    }
  }
  self.host = host
  self.reasoning = None
  self.text = None
}

///|
/// Follow live growth only after ResizeObserver reports the browser's completed
/// layout. Reading scrollHeight here therefore consumes the layout that already
/// happened instead of forcing one synchronously in the delta append path.
fn LivePreview::follow_tail_after_layout(self : LivePreview) -> Unit {
  if self.reasoning is None || !self.pinned {
    return
  }
  if @dom.document().get_element_by_id("transcript").to_option()
    is Some(transcript) {
    transcript.set_scroll_top(transcript.get_scroll_height())
  }
}

///|
/// Observe only the small live text element. The observer is reused across
/// cards but disconnected before Rabbita replaces or clears the stable host.
fn LivePreview::observe_reasoning(
  self : LivePreview,
  reasoning : @dom.Element,
) -> Unit {
  let resize = match self.resize {
    Some(resize) => resize
    None => {
      let resize = @dom.ResizeObserver::new((_, _) => {
        self.follow_tail_after_layout()
      })
      self.resize = Some(resize)
      resize
    }
  }
  resize.disconnect()
  resize.observe(reasoning)
}

///|
/// Append in place through `CharacterData.appendData`, which the typed DOM
/// package does not expose. One text node grows for the whole thought.
fn LivePreview::append_text(
  self : LivePreview,
  reasoning : @dom.Element,
  content : String,
) -> Unit {
  match self.text {
    Some(text) => {
      let _ : @js.Value = @js.Value::cast_from(text).apply_with_string(
        "appendData",
        [@js.Value::cast_from(content)],
      )
    }
    None => {
      let text = @dom.document().create_text_node(content)
      reasoning.append_child(text.as_node())
      self.text = Some(text)
    }
  }
}

///|
/// Build one activity card using Rabbita's typed DOM package. Returning the
/// reasoning element gives later frames one narrow append target.
fn LivePreview::build_card(
  self : LivePreview,
  host : @dom.Element,
  initial_content : String,
) -> @dom.Element {
  self.clear_host(Some(host))
  let document = @dom.document()
  let row = document.create_element("div")
  row.set_attribute("class", "activity-row")
  let details = document.create_element("details")
  details.set_attribute("class", "activity")
  details.set_attribute("open", "")
  let summary = document.create_element("summary")
  summary.set_attribute("class", "activity-summary")
  let summary_text = document.create_element("span")
  summary_text.set_attribute("class", "activity-text")
  if self.step_label is Some(label) {
    let step = document.create_element("span")
    step.set_attribute("class", "activity-step")
    step.append_child(document.create_text_node(label).as_node())
    summary_text.append_child(step.as_node())
    summary_text.append_child(
      document.create_text_node(" · Thinking…").as_node(),
    )
  } else {
    summary_text.append_child(
      document.create_text_node("Thinking…").as_node(),
    )
  }
  summary.append_child(summary_text.as_node())
  let body = document.create_element("div")
  body.set_attribute("class", "activity-body")
  let reasoning = document.create_element("div")
  reasoning.set_attribute(
    "class", "msg-content activity-thinking activity-thinking-live",
  )
  body.append_child(reasoning.as_node())
  details.append_child(summary.as_node())
  details.append_child(body.as_node())
  row.append_child(details.as_node())
  host.append_child(row.as_node())
  self.host = Some(host)
  self.reasoning = Some(reasoning)
  if !initial_content.is_empty() {
    self.append_text(reasoning, initial_content)
  }
  self.observe_reasoning(reasoning)
  reasoning
}

///|
/// Drain fragments received during one browser frame into the text node.
fn LivePreview::flush(self : LivePreview, target : String) -> Unit {
  self.frame = None
  if self.target != Some(target) {
    self.pending.clear()
    return
  }
  let content = StringBuilder()
  for fragment in self.pending {
    content.write_string(fragment)
  }
  self.pending.clear()
  let content = content.to_string()
  if content.is_empty() {
    return
  }
  guard live_host() is Some(host) else {
    self.clear_host(None)
    return
  }
  let reasoning = match (self.host, self.reasoning) {
    (Some(previous_host), Some(reasoning)) =>
      if previous_host.is_same_node(host.as_node()) {
        reasoning
      } else {
        self.build_card(host, "")
      }
    _ => self.build_card(host, "")
  }
  self.append_text(reasoning, content)
}

///|
fn LivePreview::sync(
  self : LivePreview,
  target : String,
  step_label : String?,
  content : String?,
) -> Unit {
  if self.target == Some(target) &&
    self.step_label == step_label &&
    self.host is Some(previous) &&
    self.reasoning is Some(_) &&
    live_host() is Some(current) &&
    previous.is_same_node(current.as_node()) {
    return
  }
  self.cancel_pending()
  self.target = Some(target)
  self.step_label = step_label
  match (content, live_host()) {
    (Some(content), Some(host)) => {
      let _ = self.build_card(host, content)
    }
    (_, host) => self.clear_host(host)
  }
}

///|
fn LivePreview::append(
  self : LivePreview,
  target : String,
  content : String,
) -> Unit {
  if content.is_empty() || self.target != Some(target) {
    return
  }
  self.pending.push(content)
  if self.frame is None {
    self.frame = Some(
      @dom.window().request_animation_frame(_ => self.flush(target)),
    )
  }
}

///|
fn LivePreview::hide(self : LivePreview, target : String) -> Unit {
  if self.target != Some(target) {
    return
  }
  self.cancel_pending()
  self.clear_host(live_host())
}

///|
fn LivePreview::reset(self : LivePreview) -> Unit {
  self.cancel_pending()
  self.target = None
  self.step_label = None
  self.clear_host(live_host())
}
