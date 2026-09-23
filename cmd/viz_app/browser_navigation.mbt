// Session navigation, scroll tracking, and keyboard behavior. Browser access
// is isolated in browser_ffi.mbt.

///|
fn hash_param(name : String) -> String? {
  read_hash_params().bind(params => params.get(name))
}

///|
fn set_hash_session(key : String, view : String) -> Unit {
  guard read_hash_params() is Some(params) else { return }
  if params.get("s") is Some(previous) && previous != key {
    params.delete("seq")
  }
  params.set("s", key)
  params.set("v", view)
  params.save()
}

///|
fn set_hash_view(view : String) -> Unit {
  set_hash_value("v", view)
}

///|
fn set_hash_value(key : String, value : String) -> Unit {
  guard read_hash_params() is Some(params) else { return }
  params.set(key, value)
  params.save()
}

///|
fn visible_elements(selector : String) -> Array[@dom.Element] {
  @dom.document()
  .query_selector_all(selector)
  .iter()
  .filter(element => element.get_client_rects().length() > 0)
  .collect()
}

///|
fn nearest_seq(want : Double) -> @dom.Element? {
  if @dom.document().get_element_by_id("seq-\{want}").to_option() is Some(exact) &&
    exact.get_client_rects().length() > 0 {
    return Some(exact)
  }
  let anchors = visible_elements("[id^='seq-']")
  for element in anchors {
    if element.get_attribute("id") is Some(id) &&
      decimal_prefix(id[4:].to_owned()) >= want {
      return Some(element)
    }
  }
  anchors.last()
}

///|
/// Retry after rendering until a visible anchor exists, including when a
/// filtered view has only a following anchor for the requested sequence.
fn restore_scroll_to_hash_seq() -> Unit {
  fn attempt(tries : Int) -> Unit {
    guard hash_param("seq") is Some(value) else { return }
    let want = decimal_prefix(value)
    if want.is_nan() || want.is_inf() {
      return
    }
    if nearest_seq(want) is Some(element) {
      element.scroll_into_view_with_options(block="start")
    } else if tries > 0 {
      let _ = @dom.window().set_timeout(() => attempt(tries - 1), 100)
    }
  }
  let _ = @dom.window().request_animation_frame(_ => {
    let _ = @dom.window().request_animation_frame(_ => attempt(50))
  })
}

///|
fn mark_scrubber(seq : Double) -> Unit {
  let mut current : @dom.Element? = None
  for segment in @dom.document().query_selector_all(".step-seg") {
    toggle_class(segment, "current", false)
    if segment.get_attribute("data-seq") is Some(value) &&
      browser_number(value) <= seq {
      current = Some(segment)
    }
  }
  if current is Some(segment) {
    toggle_class(segment, "current", true)
  }
}

///|
fn track_scroll_position() -> Unit {
  let anchors = visible_elements("[id^='seq-']")
  guard anchors.get(0) is Some(first) else { return }
  let mut best = first
  for element in anchors {
    // This reading line must stay below the CSS scroll-margin-top (105px).
    if element.get_bounding_client_rect().get_top() > 110 {
      break
    }
    best = element
  }
  guard best.get_attribute("id") is Some(id) else { return }
  let seq = id[4:].to_owned()
  if hash_param("seq") != Some(seq) {
    set_hash_value("seq", seq)
  }
  mark_scrubber(browser_number(seq))
}

///|
fn position_tracker_click(event : @dom.Event) -> Unit {
  guard event.target().to_element() is Some(target) else { return }
  if target.closest(".step-seg") is Some(segment) &&
    segment.get_attribute("data-seq") is Some(seq) &&
    seq != "" &&
    nearest_seq(browser_number(seq)) is Some(element) {
    if element.get_attribute("id") is Some(id) {
      set_hash_value("seq", id[4:].to_owned())
    }
    element.scroll_into_view_with_options(block="start")
  }
  // Rabbita handles links, so preserve the session hash when jumping from
  // the prompt rail instead of relying on the default fragment navigation.
  guard target.closest("a.rail-mark") is Some(mark) else { return }
  event.prevent_default()
  guard mark.get_attribute("href") is Some([.. "#", .. id]) &&
    id != "" &&
    @dom.document().get_element_by_id(id.to_owned()).to_option()
    is Some(element) else {
    return
  }
  if id is [.. "seq-", .. seq] {
    set_hash_value("seq", seq.to_owned())
  }
  element.scroll_into_view_with_options(block="start")
}

///|
fn install_position_tracker() -> Unit {
  let document = @dom.document()
  let events = document.as_event_target()
  let mut ticking = false
  events.add_event_listener_with_options(
    "scroll",
    _ => {
      if ticking {
        return
      }
      ticking = true
      let _ = @dom.window().request_animation_frame(_ => {
        ticking = false
        track_scroll_position()
      })
    },
    capture=true,
    passive=true,
  )
  events.add_event_listener("click", position_tracker_click)
  let tip = document.create_element("div")
  tip.set_attribute("class", "scrubber-tip")
  let style = element_style(tip)
  let hide_tip = () => style.set_property("display", "none")
  hide_tip()
  if document.get_body() is Some(body) {
    body.append_child(tip.as_node())
  }
  events.add_event_listener("mouseover", event => {
    guard event.target().to_element() is Some(target) &&
      target.closest(".step-seg") is Some(segment) &&
      segment.get_attribute("data-label") is Some(label) &&
      label != "" else {
      hide_tip()
      return
    }
    set_text_content(tip, label)
    style.set_property("display", "block")
    let rect = segment.get_bounding_client_rect()
    let width = element_offset_width(tip)
    let x = @cmp.minimum(
      @cmp.maximum(rect.get_left() + rect.get_width() / 2 - width / 2, 8),
      @dom.window().inner_width() - width - 8,
    )
    style.set_property("left", "\{x}px")
    style.set_property("top", "\{rect.get_bottom() + 6}px")
  })
  events.add_event_listener_with_options(
    "scroll",
    _ => hide_tip(),
    capture=true,
    passive=true,
  )
  events.add_event_listener("mouseleave", _ => hide_tip())
  @dom.window().to_event_target().add_event_listener("blur", _ => hide_tip())
}

///|
fn scroll_to_card_from_viewport(selector : String, direction : Int) -> Unit {
  let elements = visible_elements(selector)
  guard elements.get(0) is Some(first) && elements.last() is Some(last) else {
    return
  }
  let anchor = @dom.window().inner_height() / 2
  let target = if direction >= 0 {
    elements
    .iter()
    .find_first(element => {
      element.get_bounding_client_rect().get_top() > anchor + 1
    })
    .unwrap_or(first)
  } else {
    elements
    .rev_iter()
    .find_first(element => {
      element.get_bounding_client_rect().get_bottom() < anchor - 1
    })
    .unwrap_or(last)
  }
  target.scroll_into_view_with_options(behavior="smooth", block="center")
}

///|
fn unfold_nearest_details() -> Unit {
  let candidates = visible_elements(
    "details.card:not([open]), details.tool-call:not([open]), details.reasoning:not([open]), details.turn:not([open])",
  )
  let height = @dom.window().inner_height()
  let visible = candidates.filter(element => {
    let rect = element.get_bounding_client_rect()
    rect.get_bottom() >= 0 && rect.get_top() <= height
  })
  let pool = if visible.is_empty() { candidates } else { visible }
  let mut best : (@dom.Element, Double)? = None
  for element in pool {
    let rect = element.get_bounding_client_rect()
    let distance = (rect.get_top() + rect.get_height() / 2 - height / 2).abs()
    if best is None || (best is Some((_, previous)) && distance < previous) {
      best = Some((element, distance))
    }
  }
  if best is Some((element, _)) {
    element.set_attribute("open", "")
    element.scroll_into_view_with_options(behavior="smooth", block="nearest")
  }
}

///|
fn install_error_shortcuts(
  next : () -> Unit,
  previous : () -> Unit,
  unfold : () -> Unit,
) -> Unit {
  @dom.document()
  .as_event_target()
  .add_event_listener("keydown", event => {
    guard event.to_keyboard_event() is Some(key) else { return }
    if event.get_default_prevented() ||
      key.alt_key() ||
      key.ctrl_key() ||
      key.meta_key() {
      return
    }
    if event.target().to_element() is Some(target) {
      if target.matches("input, textarea, select") {
        return
      }
      if target.to_html_element() is Some(html) &&
        html.get_is_content_editable() {
        return
      }
    }
    let action = match key.key().to_lower() {
      "n" => next
      "p" => previous
      "u" => unfold
      _ => return
    }
    event.prevent_default()
    action()
  })
}
