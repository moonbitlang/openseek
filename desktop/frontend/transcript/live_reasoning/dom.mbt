///|
/// Imperative state for the text element inside `host_view`. It holds the
/// element Rabbita last rendered and the one text node fragments are appended
/// to; both are re-resolved whenever the rendered element changes.
priv struct LivePreview {
  mut target : String?
  mut host : @dom.Element?
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
    host: None,
    text: None,
    pending: [],
    frame: None,
    resize: None,
    pinned: true,
  }
}

///|
/// The text element Rabbita currently renders, or `None` while no transcript
/// is on screen. A different element than last time (the card was rebuilt)
/// drops the stale text node and moves the layout observer over.
fn LivePreview::acquire(self : LivePreview) -> @dom.Element? {
  guard @dom.document().get_element_by_id(TEXT_HOST_ID).to_option()
    is Some(host) else {
    self.host = None
    self.text = None
    return None
  }
  if !(self.host is Some(previous) && previous.is_same_node(host.as_node())) {
    self.host = Some(host)
    self.text = None
    self.observe(host)
  }
  Some(host)
}

///|
/// Follow live growth only after ResizeObserver reports the browser's completed
/// layout. Reading scrollHeight here therefore consumes the layout that already
/// happened instead of forcing one synchronously in the delta append path.
fn LivePreview::observe(self : LivePreview, host : @dom.Element) -> Unit {
  let resize = match self.resize {
    Some(resize) => resize
    None => {
      let resize = @dom.ResizeObserver::new((_, _) => {
        guard self.pinned else { return }
        if @dom.document().get_element_by_id("transcript").to_option()
          is Some(transcript) {
          transcript.set_scroll_top(transcript.get_scroll_height())
        }
      })
      self.resize = Some(resize)
      resize
    }
  }
  resize.disconnect()
  resize.observe(host)
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
fn LivePreview::clear(self : LivePreview, host : @dom.Element) -> Unit {
  while host.get_child_count() > 0 {
    host.remove_child(host.get_child(0))
  }
  self.text = None
}

///|
/// Append in place through `CharacterData.appendData`, which the typed DOM
/// package does not expose. One text node grows for the whole thought.
fn LivePreview::append_text(
  self : LivePreview,
  host : @dom.Element,
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
      host.append_child(text.as_node())
      self.text = Some(text)
    }
  }
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
  guard !content.is_empty() && self.acquire() is Some(host) else { return }
  self.append_text(host, content)
}

///|
fn LivePreview::sync(
  self : LivePreview,
  target : String,
  content : String?,
) -> Unit {
  self.cancel_pending()
  self.target = Some(target)
  guard self.acquire() is Some(host) else { return }
  self.clear(host)
  if content is Some(content) {
    self.append_text(host, content)
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
  if self.acquire() is Some(host) {
    self.clear(host)
  }
}

///|
fn LivePreview::reset(self : LivePreview) -> Unit {
  self.cancel_pending()
  self.target = None
  if self.acquire() is Some(host) {
    self.clear(host)
  }
}
