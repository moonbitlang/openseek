///|
/// Keep rewrites bounded while avoiding one DOM node per rendered frame. A
/// long provider fragment may occupy its own larger node; later fragments
/// start a fresh bounded chunk instead of repeatedly copying that large text.
const LIVE_TEXT_CHUNK_LIMIT = 8192

///|
/// Imperative DOM state for the childless live-reasoning host. This object is
/// captured by the component's private update closure; it is never stored in
/// a Rabbita model or exposed to the root view.
struct LivePreview {
  mut target : String?
  mut step_label : String
  mut pinned : Bool
  mut host : @dom.Element?
  mut reasoning : @dom.Element?
  mut text_chunk : @dom.Element?
  mut text_chunk_content : String
  pending : Array[String]
  mut frame : Double?
  mut resize : @dom.ResizeObserver?
}

///|
pub fn LivePreview::LivePreview() -> LivePreview {
  {
    target: None,
    step_label: "",
    pinned: true,
    host: None,
    reasoning: None,
    text_chunk: None,
    text_chunk_content: "",
    pending: [],
    frame: None,
    resize: None,
  }
}

///|
/// Cancel a queued frame before changing ownership. Clearing the fragments at
/// the same time prevents a callback from one conversation from appending to
/// a replacement conversation's card.
fn LivePreview::cancel_pending(self : LivePreview) -> Unit {
  match self.frame {
    Some(frame) => {
      @dom.window().cancel_animation_frame(frame)
      self.frame = None
    }
    None => ()
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
  match host {
    Some(host) =>
      while host.get_child_count() > 0 {
        host.remove_child(host.get_child(0))
      }
    None => ()
  }
  self.host = host
  self.reasoning = None
  self.text_chunk = None
  self.text_chunk_content = ""
}

///|
/// Follow live growth only after ResizeObserver reports the browser's completed
/// layout. Reading scrollHeight here therefore consumes the layout that already
/// happened instead of forcing one synchronously in the delta append path.
fn LivePreview::follow_tail_after_layout(self : LivePreview) -> Unit {
  if !self.pinned {
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
/// Append into a bounded current chunk. Updating one unbounded text node would
/// copy the whole preview every frame; appending one node per frame instead
/// leaves thousands of layout objects. Bounded chunks avoid both growth modes.
fn LivePreview::append_text(
  self : LivePreview,
  reasoning : @dom.Element,
  content : String,
) -> Unit {
  if self.text_chunk is Some(text_chunk) {
    let combined = self.text_chunk_content + content
    if combined.length() <= LIVE_TEXT_CHUNK_LIMIT {
      text_chunk.set_node_value(@js.Nullable::from_option(Some(combined)))
      self.text_chunk_content = combined
      return
    }
  }
  let text_chunk = @dom.document().create_text_node(content)
  reasoning.append_child(text_chunk.as_node())
  if content.length() <= LIVE_TEXT_CHUNK_LIMIT {
    self.text_chunk = Some(text_chunk)
    self.text_chunk_content = content
  } else {
    self.text_chunk = None
    self.text_chunk_content = ""
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
  if self.step_label.is_empty() {
    summary_text.append_child(
      document.create_text_node("Thinking…").as_node(),
    )
  } else {
    let step = document.create_element("span")
    step.set_attribute("class", "activity-step")
    step.append_child(document.create_text_node(self.step_label).as_node())
    summary_text.append_child(step.as_node())
    summary_text.append_child(
      document.create_text_node(" · Thinking…").as_node(),
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
/// Drain all fragments received during one browser frame. Updating one bounded
/// text chunk keeps the cost of a frame independent of the full reasoning
/// length.
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
  let document = @dom.document()
  guard document.get_element_by_id("live-reasoning-host").to_option()
    is Some(host) else {
    self.host = None
    self.reasoning = None
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
fn LivePreview::apply_sync(
  self : LivePreview,
  target : String,
  step_label : String,
  content : String,
) -> Unit {
  self.cancel_pending()
  self.target = Some(target)
  self.step_label = step_label
  let host = @dom.document()
    .get_element_by_id("live-reasoning-host")
    .to_option()
  if content.is_empty() {
    self.clear_host(host)
  } else {
    match host {
      Some(host) => {
        let _ = self.build_card(host, content)
      }
      None => {
        self.host = None
        self.reasoning = None
      }
    }
  }
}

///|
fn LivePreview::enqueue(
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
fn LivePreview::apply_hide(self : LivePreview, target : String) -> Unit {
  if self.target != Some(target) {
    return
  }
  self.cancel_pending()
  self.clear_host(
    @dom.document().get_element_by_id("live-reasoning-host").to_option(),
  )
}

///|
fn LivePreview::apply_reset(self : LivePreview) -> Unit {
  self.cancel_pending()
  self.target = None
  self.step_label = ""
  self.clear_host(
    @dom.document().get_element_by_id("live-reasoning-host").to_option(),
  )
}

///|
/// Replace the visible live-reasoning widget with one complete state. Callers
/// invoke this only from a bridge callback or an after-render command. Empty
/// content arms the target without showing a card.
pub fn LivePreview::sync(
  self : LivePreview,
  target : String,
  step_label : String,
  content : String,
) -> Unit {
  self.apply_sync(target, step_label, content)
}

///|
/// Queue one ordered reasoning fragment. All fragments received before the
/// next browser frame become one text-node append.
pub fn LivePreview::append(
  self : LivePreview,
  target : String,
  content : String,
) -> Unit {
  self.enqueue(target, content)
}

///|
/// Cache the transcript's real scroll state. The transcript capture listener
/// calls this only for scroll events; delta frames never query layout merely
/// to rediscover the same value.
pub fn LivePreview::set_pinned(self : LivePreview, pinned : Bool) -> Unit {
  self.pinned = pinned
}

///|
/// Remove a finished step's card while retaining its target. A later fragment
/// for the same run can therefore create the next card without a root render.
pub fn LivePreview::hide(self : LivePreview, target : String) -> Unit {
  self.apply_hide(target)
}

///|
/// Remove the card and disarm its target when no OpenSeek conversation owns
/// the host. A later target must arrive through `sync` before deltas are shown.
pub fn LivePreview::reset(self : LivePreview) -> Unit {
  self.apply_reset()
}
